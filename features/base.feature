Feature: Basic terminal commands
  Scenario Outline: Hello world
    Given the user starts a <shell> session
    And typo is sourced
    When the user runs "typo say hello"
    When typo has finished running
    Then stderr should be empty
    And the last line of the output should equal "hello"

    Examples:
      | shell |
      | zsh   |
      | bash  |

  Scenario Outline: Changing directories
    Given the user starts a <shell> session
    And typo is sourced

    When the user runs "typo go to the filesystem root"
    When typo has finished running
    Then stderr should be empty
    And the current directory should be "/"

    When the user runs "typo actually lets go to home dir"
    When typo has finished running
    Then stderr should be empty
    And the current directory should be "/home/node"

    When the user runs "typo switch to my movies folder"
    When typo has finished running
    Then stderr should be empty
    And the current directory should be "/home/node/MovieFolder"

    When the user runs "typo nah I prefer the previous folder we were in"
    When typo has finished running
    Then stderr should be empty
    And the current directory should be "/home/node"

    Examples:
      | shell |
      | bash  |
      | zsh   |
