Feature: Basic terminal commands
  Scenario Outline: Hello world
    Given the user starts a <shell> session
    And typo is sourced
    When the user runs "typo say hello"
    Then typo should run a command without error
    And the last line of the output should equal "hello"

    Examples:
      | shell |
      | zsh   |
      | bash  |
