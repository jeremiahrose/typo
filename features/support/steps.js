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
});

When('the user runs {string}', function (command) {
  run_command(`${command}`);
});

Then('stderr should be empty', function (callback) {
  try {
    assert.equal(errorOutput, '', 'Expected stderr to be empty, but some error output was found');
    callback();
  } catch (err) {
    callback(err);
  }
});

When('typo has finished running', function (callback) {
  const homeDir = require('os').homedir();
  const typoRunningFile = path.join(homeDir, '.typo_running');
  const timeoutLimit = 10000; // 10 seconds overall timeout

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

  const interval = setInterval(() => {
    if (typoFinished()) {
      // console.log("typo finished!");
      clearInterval(interval);
      clearTimeout(timeout); // Clear the timeout if the command finishes
      callback();
    }
  }, 500); // Poll every 500ms until the file contains 'false'

  const timeout = setTimeout(() => {
    clearInterval(interval);
    callback(new Error('Timeout: typo did not finish running in time.'));
  }, timeoutLimit); // Fail if the command doesn't finish in 10 seconds
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

After(function () {
  if (shellProcess) {
    run_command('exit');
    shellProcess.stdin.end();
  }
});
