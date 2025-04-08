# Determine the path to the installation directory when the typo function is sourced
if [ -n "$BASH_VERSION" ]; then
    TYPO_INSTALLATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    TYPO_INSTALLATION_DIR="$(cd "$(dirname "${(%):-%N}")" &>/dev/null && pwd)"
else
    echo "Unsupported shell" >&2
    return 1
fi

# Start recording the terminal session, if not already recording
if [[ -z "$terminal_log" ]]; then
  export terminal_log=$(mktemp)
  script -q -F $terminal_log
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

function typo_add_to_conversation_history() {
    local role="$1"
    local message="$2"
    if [[ -z "$message" ]]; then
        return
    fi
    # Strip null bytes and carriage returns
    message=$(printf '%s' "$message" | tr -d '\0' | tr -d '\r')
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
        "temperature": 0,
        "stream": true
    }'

    local returned_command=""

    while read -r line; do

        # Remove the 'data: ' prefix if present
        line="${line#data: }"

        # Check for the end of the stream
        if [ "$line" = "[DONE]" ]; then
            break
        fi

        # Skip empty lines
        if [ -z "$line" ]; then
            continue
        fi

        # Check for errors in the JSON response
        error_message=$(printf "%s" "$line" | jq -r '.error.message // empty')
        if [ -n "$error_message" ]; then
            echo "Error from OpenAI: $error_message" >&2
            return 1
        fi

        # Extract the 'content' from the first choice
        # Add an "x" and then strip it off so that trailing newlines are preserved: https://stackoverflow.com/a/15184414
        local content=$(
            printf "%s" "$line" | jq -r '.choices[0].delta.content // empty'
            printf x
        )
        if [ ${#content} -ge 2 ]; then
            content="${content:0:${#content}-2}"
        else
            content=""
        fi

        # Print the content to stderr as it is received
        printf '%s' "$content" >&2

        returned_command+="$content"
    done < <(curl -s https://api.openai.com/v1/chat/completions \
        --no-buffer \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "${json_body}")

    # Add a newline to the output
    echo "" >&2

    typo_add_to_conversation_history "assistant" "$returned_command"

    # Clear the terminal log
    : > $terminal_log

    if [[ "$returned_command" =~ ^# ]]; then
        echo "" >&2
    else
        if [ "${TYPO_UNSAFE_MODE:-0}" -eq 1 ]; then
            eval $returned_command
        else
            echo "Run this command (y/n)?" >&2
            if typo_get_user_confirmation; then
                eval $returned_command
            else
                echo "Command not executed."
            fi
        fi
    fi

    local command_output=$(cat $terminal_log)
    typo_add_to_conversation_history "user" "$command_output"

    echo "false" > ~/.typo_running
}
