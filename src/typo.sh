# Determine the path to the installation directory when the typo function is sourced
if [ -n "$BASH_VERSION" ]; then
    TYPO_INSTALLATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    TYPO_INSTALLATION_DIR="$(cd "$(dirname "${(%):-%N}")" &>/dev/null && pwd)"
else
    echo "Unsupported shell" >&2
    return 1
fi

typo_get_user_confirmation() {
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

    local messages=""
    if [ -z "$TYPO_CONVERSATION_HISTORY" ]; then
        messages="[{\"role\": \"system\", \"content\": $(jq -Rn --arg content "$base_prompt" '$content')}]"
    else
        messages="$TYPO_CONVERSATION_HISTORY"
    fi

    local user_message="{\"role\": \"user\", \"content\": $(jq -Rn --arg content "$input" '$content')}"
    messages=$(jq -c ". + [$user_message]" <<< "$messages")

    local json_body='{
        "model": "gpt-4o",
        "messages": '"${messages}"',
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
    printf "%s\n" "$returned_command"

    local returned_command_json="{\"role\": \"assistant\", \"content\": $(jq -Rn --arg content "$returned_command" '$content')}"
    TYPO_CONVERSATION_HISTORY=$(jq -c ". + [$returned_command_json]" <<< "$messages")

    if [[ "$returned_command" =~ ^# ]]; then
        echo ""
    else
        if [ "${TYPO_UNSAFE_MODE:-0}" -eq 1 ]; then
            eval "$returned_command"
        else
            echo "Run this command (y/n)?"
            if typo_get_user_confirmation; then
                eval "$returned_command"
            else
                echo "Command not executed."
            fi
        fi
    fi

    echo "false" > ~/.typo_running
}
