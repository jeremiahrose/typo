const { Given, When, Then, After } = require('@cucumber/cucumber');
const { spawn } = require('child_process');
const assert = require('assert');
const fs = require('fs');
const path = require('path');

let shellProcess;
let output = '';
let errorOutput = '';

Given('the user starts a {word} session', function (shell) {
  shellProcess = spawn(shell, [], { stdio: ['pipe', 'pipe', 'pipe'] });
  output = '';
  errorOutput = '';
  // Capture output
  shellProcess.stdout.on('data', (data) => {
    process.stdout.write(data.toString());
    output += data.toString();
  });

  // Capture error output
  shellProcess.stderr.on('data', (data) => {
    process.stdout.write(data.toString());
    errorOutput += data.toString();
  });
});

function run_command(cmd) {
  console.log("\x1b[32m$\x1b[0m " + cmd);
  shellProcess.stdin.write(cmd + `\n`);
}

Given('typo is sourced', function() {
  console.log();
  run_command(`source src/typo.sh`);
  run_command(`alias fd=fdfind`);
});

Given('an empty test directory', function () {
  const dirPath = '/home/node/test';
  fs.rmSync(dirPath, { recursive: true, force: true });
});

When('the user runs {string}', function (command) {
  run_command(`${command}`);
});

Then('typo should ask the user for confirmation to run a command', function(callback) {
  errorOutput = '';

  const confirmationRequested = () => {
    const lastLine = errorOutput.trimEnd().split('\n').pop().trim();
    return lastLine == "Run this command (y/n)?";
  }

  pollUntil(confirmationRequested, callback, 10000, "Timeout: typo didn't request user confirmation");
});

When('the user grants permission', function(callback) {
  setTimeout(() => {
    try {
      run_command('y');
      callback();
    } catch (err) {
      callback(err);
    }
  }, 100);
});

function pollUntil(condition, callback, timeout, timeout_message) {
  const interval = setInterval(() => {
    if (condition()) {
      clearInterval(interval);
      clearTimeout(timeout); // Clear the timeout if the command finishes
      callback();
    }
  }, 500); // Poll every 500ms until the file contains 'false'

  setTimeout(() => {
    clearInterval(interval);
    callback(new Error(timeout_message));
  }, timeout); // Fail if the command doesn't finish in 10 seconds
}

When('typo has finished running', function (callback) {
  const homeDir = require('os').homedir();
  const typoRunningFile = path.join(homeDir, '.typo_running');
  const timeout = 10000; // 10 seconds overall timeout

  const typoFinished = () => {
    try {
      // console.log("checking if typo is running...");
      const status = fs.readFileSync(typoRunningFile, 'utf8').trim();
      return status === 'false';
    } catch (error) {
      console.error('Error reading typo_running file:', error);
      return false;
    }
  };

  pollUntil(typoFinished, callback, timeout, 'Timeout: typo did not finish running in time.');
});

Then('the last line of the output should equal {string}', function (expectedOutput, callback) {
  try {
    const lastLine = output.trimEnd().split('\n').pop();
    assert.equal(lastLine, expectedOutput);
    output = '';
    callback();
  } catch (err) {
    callback(err);
  }
});

Then('the current directory should be {string}', function (expectedOutput, callback) {
  run_command(`pwd`);
  const timeout = 10000; // 10 seconds overall timeout

  const inExpectedDirectory = () => {
    const lastLine = output.trimEnd().split('\n').pop();
    return (lastLine == expectedOutput);
  }
  pollUntil(inExpectedDirectory, callback, timeout, 'Timeout: typo did not finish running in time.');
});

Then('{string} should contain exactly {string}', function (file, contents, callback) {
  try {
    const data = fs.readFileSync(file, 'utf8').trim();
    assert.equal(data, contents.replaceAll('\\n', '\n'));
    callback();
    console.log(data);
  } catch (err) {
    console.error(err);
    callback(err);
  }
});

After(function () {
  if (shellProcess) {
    run_command('exit');
    shellProcess.stdin.end();
  }
});
