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

typo_previous_command_output=""
function typo_capture_output() {
  local tmpfile=$(mktemp)           # Make a temp file
  exec 3>&1                        # Save the current stdout
  exec 1> >(tee "$tmpfile")         # Copy stdout to the temporary file
  eval "$*"                        # Run the command in the current shell
  exec 1>&3                        # Restore stdout
  sleep 1                          # Give tee a moment to finish writing to the temp file
  typo_previous_command_output=$(cat "$tmpfile")  # Read the temp file into a variable
  rm "$tmpfile"                     # Delete the temp file
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

    local previous=${typo_previous_command_output:+$'The output of your previous command was: '"${typo_previous_command_output}"$'\n\n'}
    local current="My next request is: ${input}"

    returned_command=`llm -c -m chatgpt-4o-latest "${previous}${current}" --system "$base_prompt"`
    echo "$returned_command"

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
        # fi
    fi
}
