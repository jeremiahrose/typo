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
#     "fastmcp",
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

from fastmcp import Client

from audio_util import CHANNELS, SAMPLE_RATE, AudioPlayerAsync

from openai import AsyncOpenAI
from openai.types.beta.realtime.session import Session
from openai.resources.beta.realtime.realtime import AsyncRealtimeConnection


class MCPClient:
    """MCP client for connecting to and managing MCP servers."""

    def __init__(self):
        self.available_tools: list[dict] = []
        self.client = None

    async def connect_to_mcp_servers(self):
        """Connect to MCP servers defined in configuration."""
        print("Starting MCP servers...")

        # Load configuration from mcp.json file
        try:
            with open("mcp.json", "r") as f:
                config = json.load(f)
            print("✓ Loaded MCP configuration from mcp.json")
        except FileNotFoundError:
            print("⚠ mcp.json not found, using empty configuration")
            config = {
                "mcpServers": {}
            }
        except json.JSONDecodeError as e:
            print(f"✗ Error parsing mcp.json: {e}")
            raise

        # Create and validate client with FastMCP
        try:
            self.client = Client(config)
            print("✓ FastMCP configuration validated")
        except Exception as e:
            print(f"✗ FastMCP configuration validation failed: {e}")
            raise

        print("Discovering tools...")
        # Connect and get available tools
        async with self.client as client:
            tools = await client.list_tools()
            self.available_tools = []

            for tool in tools:
                # Convert MCP tool to OpenAI function format
                openai_tool = {
                    "type": "function",
                    "name": tool.name,
                    "description": tool.description or f"MCP tool: {tool.name}",
                    "parameters": tool.inputSchema or {"type": "object", "properties": {}, "required": []}
                }
                self.available_tools.append(openai_tool)

            print(f"Found {len(self.available_tools)} tools")

    async def call_tool(self, tool_name: str, arguments: dict) -> dict:
        """Execute a tool call on the MCP server."""
        if not self.client:
            return {"error": "No MCP server configured"}

        try:
            async with self.client as client:
                result = await client.call_tool(tool_name, arguments)
                return {
                    "success": True,
                    "content": result.content if hasattr(result, 'content') else [{"type": "text", "text": str(result)}],
                    "isError": False
                }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "isError": True
            }

    def serialize_mcp_result(self, result: dict) -> dict:
        """Convert MCP result to JSON-serializable format."""
        serializable_result = {
            "success": result.get("success", False),
            "isError": result.get("isError", False)
        }

        # Convert content objects to strings
        content = result.get("content", [])
        content_strings = []
        for item in content:
            if hasattr(item, 'type') and item.type == "text":
                content_strings.append(item.text)
            elif isinstance(item, dict) and item.get("type") == "text":
                content_strings.append(item.get('text', ''))
            else:
                content_strings.append(str(item))

        serializable_result["content"] = "\n".join(content_strings) if content_strings else ""

        # Add error if present
        if "error" in result:
            serializable_result["error"] = result["error"]

        return serializable_result

    def print_result(self, tool_name: str, args: dict, result: dict) -> None:
        """Print MCP tool execution result to terminal."""
        print(f"\n🔧 MCP Tool: {tool_name}")
        if args:
            print(f"Arguments: {args}")

        # Display the result
        if result.get("success"):
            print("✓ Success")
            content = result.get("content", [])

            for item in content:
                if hasattr(item, 'type') and item.type == "text":
                    print(f"  {item.text}")
                elif isinstance(item, dict) and item.get("type") == "text":
                    print(f"  {item.get('text', '')}")
                else:
                    print(f"  {str(item)}")

            if result.get("isError"):
                print("⚠ Tool reported an error")
        else:
            print("✗ Failed")
            error = result.get("error", "Unknown error")
            print(f"  {error}")

        print()  # Add blank line for spacing

    async def close(self):
        """Close the MCP client connection."""
        # FastMCP Client uses async context managers, no explicit close needed
        pass


class RealtimeApp:

    def __init__(self) -> None:
        self.connection = None
        self.session = None
        self.client = AsyncOpenAI()
        self.audio_player = AudioPlayerAsync()
        self.last_audio_item_id = None
        self.should_send_audio = asyncio.Event()
        self.connected = asyncio.Event()
        self.mcp_client = MCPClient()
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
        self.mcp_task = asyncio.create_task(self.initialize_mcp())

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
        if hasattr(self, 'mcp_task'):
            self.mcp_task.cancel()

        # Close MCP client
        await self.mcp_client.close()

        # Wait for tasks to finish cancelling
        tasks = []
        if hasattr(self, 'realtime_task'):
            tasks.append(self.realtime_task)
        if hasattr(self, 'audio_task'):
            tasks.append(self.audio_task)
        if hasattr(self, 'mcp_task'):
            tasks.append(self.mcp_task)

        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def initialize_mcp(self) -> None:
        """Initialize MCP client connection."""
        print("Connecting to MCP servers...")

        try:
            await self.mcp_client.connect_to_mcp_servers()
            print(f"✓ MCP servers connected with {len(self.mcp_client.available_tools)} tools")
        except Exception as e:
            print(f"✗ MCP connection failed: {e}")
            # Don't let MCP failure stop the app

    async def handle_realtime_connection(self) -> None:
        try:
            async with self.client.beta.realtime.connect(model="gpt-4o-realtime-preview") as conn:
                self.connection = conn
                self.connected.set()

                # Wait for MCP client to be ready
                max_wait = 10  # seconds
                wait_count = 0
                while not self.mcp_client.available_tools and wait_count < max_wait:
                    await asyncio.sleep(1)
                    wait_count += 1

                # Configure session with MCP tools and built-in commands
                tools = [
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
                ]

                # Add MCP tools if available
                tools.extend(self.mcp_client.available_tools)

                await conn.session.update(session={
                    "turn_detection": {"type": "server_vad"},
                    "tools": tools,
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


    def get_sync_user_approval(self, tool_name: str, args: dict) -> bool:
        """Get user approval for tool execution (sync version)."""
        print(f"\n🔧 Tool Call Request: {tool_name}")
        if args:
            print(f"Arguments: {json.dumps(args, indent=2)}")
        
        while True:
            try:
                response = input("Approve this tool call? [y/N]: ").strip().lower()
                if response in ['y', 'yes']:
                    return True
                elif response in ['n', 'no', '']:
                    return False
                else:
                    print("Please enter 'y' for yes or 'n' for no.")
            except (EOFError, KeyboardInterrupt):
                print("\nTool call denied.")
                return False

    async def handle_function_call(self, function_call_item: Any) -> None:
        """Handle function calls from the model."""
        tool_name = function_call_item.name

        # Parse the function arguments
        try:
            args = json.loads(function_call_item.arguments)
        except json.JSONDecodeError:
            args = {}

        # Get user approval for tool execution
        approved = await asyncio.get_event_loop().run_in_executor(None, lambda: self.get_sync_user_approval(tool_name, args))
        
        if not approved:
            print("❌ Tool call denied by user")
            # Send denial result back to the model
            connection = await self._get_connection()
            await connection.conversation.item.create(
                item={
                    "type": "function_call_output",
                    "call_id": function_call_item.call_id,
                    "output": json.dumps({"error": "Tool call denied by user"})
                }
            )
            await connection.response.create()
            return

        if tool_name == "run_command":
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

        else:
            # Handle MCP tool calls
            # Execute the MCP tool
            result = await self.mcp_client.call_tool(tool_name, args)

            # Display the result
            self.mcp_client.print_result(tool_name, args, result)

            # Send function call result back to the model
            connection = await self._get_connection()
            await connection.conversation.item.create(
                item={
                    "type": "function_call_output",
                    "call_id": function_call_item.call_id,
                    "output": json.dumps(self.mcp_client.serialize_mcp_result(result))
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
