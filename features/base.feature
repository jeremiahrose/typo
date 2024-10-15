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
