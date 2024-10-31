# Determine the path to the installation directory when the typo function is sourced
if [ -n "$BASH_VERSION" ]; then
    TYPO_INSTALLATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    TYPO_INSTALLATION_DIR="$(cd "$(dirname "${(%):-%N}")" &>/dev/null && pwd)"
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

function typo_capture_output() {
  local tmpfile=$(mktemp)           # Make a temp file
  exec 3>&1                        # Save the current stdout
  exec 1> >(tee "$tmpfile")         # Copy stdout to the temporary file
  eval "$*"                        # Run the command in the current shell
  exec 1>&3                        # Restore stdout
  sleep 1                          # Give tee a moment to finish writing to the temp file
  command_output=$(cat "$tmpfile")  # Read the temp file into a variable
  rm "$tmpfile"                     # Delete the temp file
}

function typo_add_to_conversation_history() {
    local role="$1"
    local message="$2"
    if [[ -z "$message" ]]; then
        return
    fi
    local message_json="{\"role\": \"$role\", \"content\": $(jq -Rn --arg content "$message" '$content')}"
    TYPO_CONVERSATION_HISTORY=$(jq -c ". + [$message_json]" <<< "$TYPO_CONVERSATION_HISTORY")
}

function typo() {
    echo "true" > ~/.typo_running

    if ! command -v jq &>/dev/null; then
        echo "jq is not installed"
        return 1
    fi

    if ! command -v fzf &>/dev/null; then
        echo "fzf is not installed"
        return 1
    fi

    if ! command -v fd &>/dev/null && ! command -v fdfind &>/dev/null; then
        echo "fd is not installed"
        return 1
    fi

    if ! command -v fdfind &>/dev/null; then
        alias fdfind=fd
    fi

    if [ "$#" -gt 0 ]; then
        input="$*"
    elif [ -p /dev/stdin ]; then
        input=$(cat)
    else
        input=""
    fi

    if [ -z "$OPENAI_API_KEY" ]; then
        echo "Error: OPENAI_API_KEY is not set."
        return 1
    fi

    local prompts_dir="${TYPO_INSTALLATION_DIR}/active_prompts"
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

    if [ -z "$TYPO_CONVERSATION_HISTORY" ]; then
        TYPO_CONVERSATION_HISTORY="[{\"role\": \"system\", \"content\": $(jq -Rn --arg content "$base_prompt" '$content')}]"
    fi

    typo_add_to_conversation_history "user" "$input"

    local json_body='{
        "model": "gpt-4o",
        "messages": '"${TYPO_CONVERSATION_HISTORY}"',
        "temperature": 0
    }'

    local response=$(curl -s https://api.openai.com/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d "${json_body}"
    )

    local error_message=$(printf "%s" "$response" | jq -r '.error.message // empty')
    if [ -n "$error_message" ]; then
        echo "Error from OpenAI: $error_message"
        return 1
    fi

    local returned_command=$(printf "%s" "$response" | jq -r '.choices[0].message.content')
    printf "%s\n" "$returned_command" >&2

    typo_add_to_conversation_history "assistant" "$returned_command"

    local command_output=""

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

    typo_add_to_conversation_history "user" "$command_output"

    echo "false" > ~/.typo_running
}
