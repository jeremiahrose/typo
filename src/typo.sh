# Determine the path to the installation directory when the typo function is sourced
if [ -n "$BASH_VERSION" ]; then
    typo_installation_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    typo_installation_dir="$(cd "$(dirname "${(%):-%N}")" &>/dev/null && pwd)"
else
    echo "Unsupported shell" >&2
    return 1
fi

function typo_get_user_confirmation() {
    if [ -n "$BASH_VERSION" ]; then
        read -t 0.2 -n 10 drain < /dev/tty
        read choice
    elif [ -n "$ZSH_VERSION" ]; then
        read -t 0.2 -k 10 drain < /dev/tty
        read "choice?"
    fi

    if [[ "$choice" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

function typo_get_audio_prompt() {
    file_path="/tmp/typo/rec_$(uuidgen 2>/dev/null).mp3"
    mkdir -p "$(dirname "$file_path")"
    printf "Recording (q to stop)... " >&2
    ffmpeg -y -loglevel quiet -nostats -f avfoundation -i ":0" -ac 1 -ar 44100 -codec:a libmp3lame -qscale:a 2 "$file_path" 2>/dev/null
    echo "Done" >&2
    printf "$file_path"
}

typo_command_output=""
function typo_capture_output() {
  local tmpfile=$(mktemp)           # Make a temp file
  exec 3>&1                        # Save the current stdout
  exec 1> >(tee "$tmpfile")         # Copy stdout to the temporary file
  eval "$*"                        # Run the command in the current shell
  exec 1>&3                        # Restore stdout
  sleep 1                          # Give tee a moment to finish writing to the temp file
  typo_command_output=$(cat "$tmpfile")  # Read the temp file into a variable
  rm "$tmpfile"                     # Delete the temp file
}

typo_conversation_history="Conversation began as follows..."$'\n\n'
function typo_add_to_conversation_history() {
    local prompt="$1"
    local command="$2"

    typo_conversation_history="${typo_conversation_history}User said: $prompt"$'\n'"You responded with command: $command"$'\n\n'
}

function typo() {
    if ! command -v jq &>/dev/null; then
        echo "jq is not installed"
        return 1
    fi

    if ! command -v fzf &>/dev/null; then
        echo "fzf is not installed"
        return 1
    fi

    if ! command -v llm &>/dev/null; then
        echo "llm is not installed"
        return 1
    fi

    if ! command -v ffmpeg &>/dev/null; then
        echo "ffmpeg is not installed"
        return 1
    fi

    if ! command -v fd &>/dev/null && ! command -v fdfind &>/dev/null; then
        echo "fd is not installed"
        return 1
    fi

    if ! command -v fdfind &>/dev/null; then
        alias fdfind=fd
    fi

    # Check for --audio argument
    local audio_mode=false
    [[ $1 == --audio ]] && { audio_mode=true; shift; }

    if [ "$#" -gt 0 ]; then
        text_prompt="$*"
    elif [ -p /dev/stdin ]; then
        text_prompt=$(cat)
    else
        text_prompt=""
    fi

    if [ -z "$OPENAI_API_KEY" ]; then
        echo "Error: OPENAI_API_KEY is not set."
        return 1
    fi

    local prompts_dir="${typo_installation_dir}/active_prompts"
    local base_prompt=$(cat "${prompts_dir}/base.txt")

    for file in "${prompts_dir}"/*; do
        if [ "$file" != "${prompts_dir}/base.txt" ] && [ -f "$file" ]; then
            base_prompt="${base_prompt}"$'\n'"$(cat "$file")"
        fi
    done

    if [ -n "$TYPO_CUSTOM_PROMPTS_DIR" ] && [ -d "$TYPO_CUSTOM_PROMPTS_DIR" ] && [ "$(ls -A "$TYPO_CUSTOM_PROMPTS_DIR")" ]; then
        for file in "${TYPO_CUSTOM_PROMPTS_DIR}"/*; do
            if [ -f "$file" ]; then
                base_prompt="${base_prompt}"$'\n'"$(cat "$file")"
            fi
        done
    fi

    if $audio_mode; then
        audio_prompt=$(typo_get_audio_prompt)
        returned_command=`llm -m gpt-4o-audio-preview "${typo_conversation_history}" --system "$base_prompt" -a "$audio_prompt"`
    else
        current="User says: ${text_prompt}"
        returned_command=`llm -m chatgpt-4o-latest "${typo_conversation_history}${current}" --system "$base_prompt"`
    fi

    echo "$returned_command"

    # TODO get model to transcribe prompt in audio mode
    typo_add_to_conversation_history "$text_prompt" "$returned_command"

    if [[ "$returned_command" =~ ^# ]]; then
        echo "" >&2
    else
        if [ "${TYPO_UNSAFE_MODE:-0}" -eq 1 ]; then
            typo_capture_output "$returned_command"
        else
            echo "Run this command (y/n)?" >&2
            if typo_get_user_confirmation; then
                typo_capture_output "$returned_command"
            else
                echo "Command not executed."
            fi
        fi
    fi
}
