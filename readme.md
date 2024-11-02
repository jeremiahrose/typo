# typo

`typo` is a terminal based AI agent for controlling your computer with natural language.

## Examples

Cloning a git repo

```zsh
jez@mac ~  % typo clone the main pytorch repo into my personal code dir
fd . ~ /Applications --max-depth 7 -E Library | fzf -f "code" --scheme=path | head -n 30 | typo
Cloning into '/Users/jez/Code/pytorch'...
remote: Enumerating objects: 1021787, done.
remote: Counting objects: 100% (2672/2672), done.
remote: Compressing objects: 100% (1459/1459), done.
Receiving objects:  11% (116544/1021787), 60.56 MiB | 3.14 MiB/
```

Playing chess

```zsh
jez@mac ~  % typo play chess with me
fd . ~ /Applications --max-depth 7 -E Library | fzf -f "chess" --scheme=path | head -n 30 | typo
open -a "Chess"
```

Creating a spreadsheet

```zsh
jez@mac ~ % typo generate a csv file containing a list of delicious fruits followed by their main regions of production
echo -e "Fruit,Region\n🍎 Apple,China\n🍓 Strawberry,USA\n🍍 Pineapple,Philippines\n🍇 Grapes,Italy\n🍉 Watermelon,China\n🍒 Cherry,Turkey\n🥭 Mango,India\n🍑 Peach,China\n🍊 Orange,Brazil\n🥝 Kiwi,Italy\n🍋 Lemon,Mexico\n🍈 Melon,Turkey" > delicious_fruits.csv
jez@mac ~ % typo open it as a spreadsheet
open -a "Numbers" delicious_fruits.csv
jez@mac ~ % typo I dont like kiwis, please remove them and rearrange in alphabetical order
grep -v "🥝 Kiwi" delicious_fruits.csv | sort > temp.csv && mv temp.csv delicious_fruits.csv && open -a "Numbers" delicious_fruits.csv
Run this command (y/n)? y
```

## Features
- Uses the ChatGPT LLM to obtain shell commands to satisfy a request in natural language
- Requires an OpenAI API account and token
- Searches for files and apps and intelligently chooses the correct one
- Asks for confirmation before running any command
- Written for `zsh` but should also work in `bash`
- Can return a sequence of commands and knows how to pipe command output to itself to obtain more information
- Can be extended and customised in natural language

## Limitations
- A Usage tier 2 or higher OpenAI account is recommended for best results.

## Installation (MacOS)
1. `brew tap jeremiahrose/typo`
2. `brew install typo`
3. Add the following to your `.zshrc` file:
```zsh
# Load typo (your path may be different)
source /opt/homebrew/opt/typo/typo.sh
# Export your OpenAI API key so typo can connect to GPT4o
export OPENAI_API_KEY=your_key
# Set a custom prompts directory
export TYPO_CUSTOM_PROMPTS_DIR=your_custom_prompts_dir
```
4. Customise behaviour by adding prompts to your custom prompts directory specified by `TYPO_CUSTOM_PROMPTS_DIR`
5. Upload your new and useful prompts as a PR to this repository :)
