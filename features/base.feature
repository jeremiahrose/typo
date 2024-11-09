Feature: Basic terminal commands
  Scenario Outline: Hello world
    Given the user starts a <shell> session
    And typo is sourced
    When the user runs "typo say hello"
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    When typo has finished running
    And the last line of the output should equal "hello"

    Examples:
      | shell |
      | zsh   |
      | bash  |

  Scenario Outline: Changing directories
    Given the user starts a <shell> session
    And typo is sourced

    When the user runs "typo go to the filesystem root"
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    When typo has finished running
    And the current directory should be "/"

    When the user runs "typo actually lets go to home dir"
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    When typo has finished running
    And the current directory should be "/home/node"

    When the user runs "typo switch to my movies folder"
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    When typo has finished running
    And the current directory should be "/home/node/MovieFolder"

    When the user runs "typo nah I prefer the previous folder we were in"
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    When typo has finished running
    And the current directory should be "/home/node"

    Examples:
      | shell |
      | bash  |
      | zsh   |

  Scenario Outline: Editing files
    Given an empty test directory
    And the user starts a <shell> session
    And typo is sourced

    When the user runs "typo make a new test folder in my home dir and go to it"
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    When typo has finished running
    And the current directory should be "/home/node/test"

    When the user runs "typo make a fib.csv file with the top row containing the first 10 fibonacci numbers"
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    When typo has finished running
    And "/home/node/test/fib.csv" should contain exactly "0,1,1,2,3,5,8,13,21,34"

    When the user runs "typo now add one to each of the numbers"
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    And typo has finished running
    And "/home/node/test/fib.csv" should contain exactly "1,2,2,3,4,6,9,14,22,35"

    When the user runs "typo now duplicate the first line twice so there are exactly three lines"
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    And typo has finished running
    And "/home/node/test/fib.csv" should contain exactly "1,2,2,3,4,6,9,14,22,35\n1,2,2,3,4,6,9,14,22,35\n1,2,2,3,4,6,9,14,22,35"

    When the user runs "typo replace the '9' on the second line with 'prawn'"
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    And typo has finished running
    And "/home/node/test/fib.csv" should contain exactly "1,2,2,3,4,6,9,14,22,35\n1,2,2,3,4,6,prawn,14,22,35\n1,2,2,3,4,6,9,14,22,35"

    When the user runs "typo convert the whole thing to a json array using raw integers where possible and save to fib.json"
    Then typo should ask the user for confirmation to run a command
    When the user grants permission
    And typo has finished running
    And "/home/node/test/fib.json" should contain exactly "[[1,2,2,3,4,6,9,14,22,35],[1,2,2,3,4,6,\"prawn\",14,22,35],[1,2,2,3,4,6,9,14,22,35]]"

    Examples:
      | shell |
      | bash  |
      | zsh   |
