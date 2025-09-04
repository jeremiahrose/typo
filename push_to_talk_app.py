#!/usr/bin/env uv run
####################################################################
# Push to talk terminal app interface to the Realtime API         #
# If you have `uv` installed and the `OPENAI_API_KEY`              #
# environment variable set, you can run this example with just     #
#                                                                  #
# `./push_to_talk_app.py`                                          #
#                                                                  #
# On Mac, you'll also need `brew install portaudio ffmpeg`           #
####################################################################
#
# /// script
# requires-python = ">=3.9"
# dependencies = [
#     "numpy",
#     "pyaudio",
#     "pydub",
#     "sounddevice",
#     "openai[realtime]",
# ]
#
# ///
from __future__ import annotations

import base64
import asyncio
import json
import subprocess
import sys
from typing import Any, cast

from audio_util import CHANNELS, SAMPLE_RATE, AudioPlayerAsync

from openai import AsyncOpenAI
from openai.types.beta.realtime.session import Session
from openai.resources.beta.realtime.realtime import AsyncRealtimeConnection


class RealtimeApp:

    def __init__(self) -> None:
        self.connection = None
        self.session = None
        self.client = AsyncOpenAI()
        self.audio_player = AudioPlayerAsync()
        self.last_audio_item_id = None
        self.should_send_audio = asyncio.Event()
        self.connected = asyncio.Event()
        self.is_recording = False
        self.response_started = False


    async def start(self) -> None:
        """Start the application."""
        print("🔊 GPT Audio Control - Terminal Version")
        print("Press 'k' + Enter to start/stop recording, 'q' + Enter to quit")
        print("" + "="*50)
        
        # Start background tasks and keep references
        self.realtime_task = asyncio.create_task(self.handle_realtime_connection())
        self.audio_task = asyncio.create_task(self.send_mic_audio())
        
        try:
            # Handle user input
            await self.handle_input()
        except KeyboardInterrupt:
            print("\nShutting down...")
        finally:
            await self.cleanup()

    async def cleanup(self) -> None:
        """Clean up background tasks and connections."""
        print("Cleaning up...")
        
        # Cancel background tasks
        if hasattr(self, 'realtime_task'):
            self.realtime_task.cancel()
        if hasattr(self, 'audio_task'):
            self.audio_task.cancel()
        
        # Wait for tasks to finish cancelling
        tasks = []
        if hasattr(self, 'realtime_task'):
            tasks.append(self.realtime_task)
        if hasattr(self, 'audio_task'):
            tasks.append(self.audio_task)
            
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def handle_realtime_connection(self) -> None:
        try:
            async with self.client.beta.realtime.connect(model="gpt-4o-realtime-preview") as conn:
                self.connection = conn
                self.connected.set()

                # Configure session with function calling enabled
                await conn.session.update(session={
                    "turn_detection": {"type": "server_vad"},
                    "tools": [
                        {
                            "type": "function",
                            "name": "run_command",
                            "description": "Execute a bash command on the user's system.",
                            "parameters": {
                                "type": "object",
                                "properties": {
                                    "command": {
                                        "type": "string",
                                        "description": "The bash command to execute"
                                    }
                                },
                                "required": ["command"]
                            }
                        }
                    ],
                    "tool_choice": "auto"
                })

                acc_items: dict[str, Any] = {}

                async for event in conn:
                    if event.type == "session.created":
                        self.session = event.session
                        continue

                    if event.type == "session.updated":
                        self.session = event.session
                        continue

                    if event.type == "response.audio.delta":
                        if event.item_id != self.last_audio_item_id:
                            self.audio_player.reset_frame_count()
                            self.last_audio_item_id = event.item_id

                        bytes_data = base64.b64decode(event.delta)
                        self.audio_player.add_data(bytes_data)
                        continue

                    if event.type == "response.audio_transcript.delta":
                        # Print the AI prefix only once when starting a new response
                        if not self.response_started:
                            print("🤖 AI: ", end="", flush=True)
                            self.response_started = True
                        
                        # Simply print the delta text (new characters only)
                        print(event.delta, end="", flush=True)
                        continue

                    if event.type == "response.done":
                        # Print newline after response is complete
                        if self.response_started:
                            print()  # Move to new line after streaming is complete
                            self.response_started = False
                            
                        # Check if response contains function calls
                        if hasattr(event, 'response') and hasattr(event.response, 'output'):
                            for output_item in event.response.output:
                                if hasattr(output_item, 'type') and output_item.type == "function_call":
                                    await self.handle_function_call(output_item)
                        continue
        except asyncio.CancelledError:
            # Task was cancelled, exit gracefully
            pass
        except Exception as e:
            print(f"Realtime connection error: {e}")

    async def _get_connection(self) -> AsyncRealtimeConnection:
        await self.connected.wait()
        assert self.connection is not None
        return self.connection

    async def handle_function_call(self, function_call_item: Any) -> None:
        """Handle function calls from the model."""
        if function_call_item.name == "run_command":
            # Parse the function arguments
            args = json.loads(function_call_item.arguments)
            command = args.get("command", "")
            
            # Display command
            print(f"\n💻 Command: {command}")
            
            # Execute the command
            try:
                result = subprocess.run(
                    command,
                    shell=True,
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                
                # Display the output
                if result.stdout:
                    print("✓ Output:")
                    print(f"  {result.stdout.strip()}")
                
                if result.stderr:
                    print("⚠ Error:")
                    print(f"  {result.stderr.strip()}")
                
                # Show return code if non-zero
                if result.returncode != 0:
                    print(f"Exit code: {result.returncode}")
                
                command_result = {
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                    "returncode": result.returncode
                }
                
            except subprocess.TimeoutExpired:
                print("⚠ Command timed out (30s)")
                command_result = {"error": "Command timed out after 30 seconds"}
                
            except Exception as e:
                print(f"⚠ Error executing command: {str(e)}")
                command_result = {"error": f"Failed to execute: {str(e)}"}
            
            print()  # Add blank line for spacing
            
            # Send function call result back to the model
            connection = await self._get_connection()
            await connection.conversation.item.create(
                item={
                    "type": "function_call_output",
                    "call_id": function_call_item.call_id,
                    "output": json.dumps(command_result)
                }
            )
            
            # Generate a response from the model
            await connection.response.create()

    async def send_mic_audio(self) -> None:
        import sounddevice as sd  # type: ignore

        sent_audio = False

        device_info = sd.query_devices()
        print(device_info)

        read_size = int(SAMPLE_RATE * 0.02)

        stream = sd.InputStream(
            channels=CHANNELS,
            samplerate=SAMPLE_RATE,
            dtype="int16",
        )
        stream.start()

        try:
            while True:
                if stream.read_available < read_size:
                    await asyncio.sleep(0)
                    continue

                await self.should_send_audio.wait()
                self.is_recording = True

                data, _ = stream.read(read_size)

                connection = await self._get_connection()
                if not sent_audio:
                    asyncio.create_task(connection.send({"type": "response.cancel"}))
                    sent_audio = True

                await connection.input_audio_buffer.append(audio=base64.b64encode(cast(Any, data)).decode("utf-8"))

                await asyncio.sleep(0)
        except asyncio.CancelledError:
            # Task was cancelled, exit gracefully
            pass
        except KeyboardInterrupt:
            pass
        except Exception as e:
            print(f"Audio error: {e}")
        finally:
            stream.stop()
            stream.close()

    async def handle_input(self) -> None:
        """Handle user input from terminal."""
        import asyncio
        
        loop = asyncio.get_event_loop()
        
        def get_input():
            return input()
        
        try:
            while True:
                status = "🔴 Recording... (Press 'k' + Enter to stop)" if self.is_recording else "⚪ Press 'k' + Enter to start recording ('q' + Enter to quit)"
                print(f"\n{status}")
                
                try:
                    user_input = await loop.run_in_executor(None, get_input)
                    
                    if user_input == "q":
                        print("Goodbye!")
                        return
                    
                    if user_input == "k":
                        if self.is_recording:
                            self.should_send_audio.clear()
                            self.is_recording = False
                            print("⏹ Recording stopped")
                            
                            if self.session and self.session.turn_detection is None:
                                # The default in the API is that the model will automatically detect when the user has
                                # stopped talking and then start responding itself.
                                #
                                # However if we're in manual `turn_detection` mode then we need to
                                # manually tell the model to commit the audio buffer and start responding.
                                conn = await self._get_connection()
                                await conn.input_audio_buffer.commit()
                                await conn.response.create()
                        else:
                            self.should_send_audio.set()
                            self.is_recording = True
                            print("▶️ Recording started")
                            
                except EOFError:
                    break
                    
        except KeyboardInterrupt:
            print("\nGoodbye!")


async def main():
    app = RealtimeApp()
    try:
        await app.start()
    except KeyboardInterrupt:
        print("\nGoodbye!")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass  # Graceful shutdown