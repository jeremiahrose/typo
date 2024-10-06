# Determine the path to the installation directory when the typo function is sourced
if [ -n "$BASH_VERSION" ]; then
    G_INSTALLATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    G_INSTALLATION_DIR="$(cd "$(dirname "${(%):-%N}")" &>/dev/null && pwd)"
else
    echo "Unsupported shell" >&2
    return 1
fi

function typo() {
    set -e # Exit on error

    if [ "$#" -gt 0 ]; then
        input="$*"
    elif [ -p /dev/stdin ]; then
        input=$(cat)
    else
        echo "No input provided"
        return 1
    fi

    # Check for OpenAI key
    if [ -z "$OPENAI_API_KEY" ]; then
        echo "Error: OPENAI_API_KEY is not set."
        return 1
    fi

    # Construct system prompt by concatenating text files. Base prompt first, then the others in arbitrary order.
    local prompts_dir="${G_INSTALLATION_DIR}/active_prompts"
    local base_prompt=$(cat "${prompts_dir}/base.txt"; for file in $(ls "${prompts_dir}" | grep -v 'base.txt'); do echo ""; cat "$prompts_dir/$file"; done)

    # Initialise conversation history
    local messages=""
    if [ -z "$G_CONVERSATION_HISTORY" ]; then
        # If there is no history, start with the base prompt
        messages="[{\"role\": \"system\", \"content\": $(jq -Rn --arg content "$base_prompt" '$content')}]"
    else
        # Otherwise use the existing conversation history
        messages="$G_CONVERSATION_HISTORY"
    fi

    # Append user input to the conversation
    local user_message="{\"role\": \"user\", \"content\": $(jq -Rn --arg content "$input" '$content')}"
    messages=$(jq -c ". + [$user_message]" <<< "$messages")

    # Construct the API request
    local json_body='{
        "model": "gpt-4o",
        "messages": '"${messages}"',
        "temperature": 0.7
    }'

    # Send request to OpenAI API
    local response=$(curl -s https://api.openai.com/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d "${json_body}"
    )

    # Check for an error in the response
    local error_message=$(printf "%s" "$response" | jq -r '.error.message // empty')
    if [ -n "$error_message" ]; then
        echo "Error from OpenAI: $error_message"
        return 1
    fi

    # Parse and print the returned command
    local returned_command=$(printf "%s" "$response" | jq -r '.choices[0].message.content')
    printf "%s\n" "$returned_command"

    # Append the returned command to conversation
    local returned_command_json="{\"role\": \"assistant\", \"content\": $(jq -Rn --arg content "$returned_command" '$content')}"
    G_CONVERSATION_HISTORY=$(jq -c ". + [$returned_command_json]" <<< "$messages")

    # Define a list of dangerous commands
    local dangerous_commands=("rm" "mv" "cp" "chmod" "chown" "chgrp" "dd" "shutdown" "reboot" "init" "telinit" "kill" "killall" "pkill" "mkfs" "fsck" "fdisk" "ln" "sudo" "su" "rmdir" "mkfs" "ipfw" "blkdiscard" "hdparm" "systemd" "alias" "poweroff" "exit")

    # Check if the returned command contains any dangerous commands
    if echo "$returned_command" | egrep -qw '('"$(IFS='|'; echo "${dangerous_commands[*]}")"')'; then
        # Command is dangerous, ask for confirmation before running
        read -t 0.2 -k 10 drain < /dev/tty
        read "choice?Run this command (y/n)? " < /dev/tty
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            eval "$returned_command"
        else
            echo "Command not executed."
        fi
    else
        # Command is considered safe, run automatically
        eval "$returned_command"
    fi
}
