const { Given, When, Then, After } = require('@cucumber/cucumber');
const { spawn } = require('child_process');
const assert = require('assert');

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
  shellProcess.stdin.write(cmd + `\n`);
}

Given('typo is sourced', function() {
  run_command(`source src/typo.sh`);
});

When('the user runs {string}', function (command) {
  run_command(`${command}`);
});

Then('typo should run a command without error', function (callback) {
  setTimeout(() => {
    try {
      assert.equal(errorOutput, '', 'Expected stderr to be empty, but some error output was found');
      callback();
    } catch (err) {
      callback(err);
    }
  }, 1000);
});

Then('the last line of the output should equal {string}', function (expectedOutput, callback) {
  setTimeout(() => {
    try {
      const lastLine = output.trimEnd().split('\n').pop();
      assert.equal(lastLine, expectedOutput);
      output = '';
      callback();
    } catch (err) {
      callback(err);
    }
  }, 1000);
});

After(function () {
  if (shellProcess) {
    run_command('exit');
    shellProcess.stdin.end();
  }
});
