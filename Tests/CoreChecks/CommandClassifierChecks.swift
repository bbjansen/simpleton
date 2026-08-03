// Tests/CoreChecks/CommandClassifierChecks.swift
import SimpletonCore

func runCommandClassifierChecks(_ t: TestRunner) {
    t.suite("CommandClassifier.isSafe — read-only commands are safe") {
        for cmd in ["ls", "ls -la", "pwd", "whoami", "hostname", "date",
                    "git status", "git log --oneline", "git diff HEAD",
                    "cat README.md", "grep foo file.txt", "df -h", "docker ps"] {
            t.expect(CommandClassifier.isSafe(cmd), "'\(cmd)' should be safe")
        }
    }

    t.suite("CommandClassifier.isSafe — shell operators force unsafe (regression for 8d3ceac)") {
        for cmd in ["ls | grep foo", "cat a && rm b", "echo hi || rm -rf /",
                    "ls; rm x", "echo hi > file", "cat >> file", "sort < file"] {
            t.expect(!CommandClassifier.isSafe(cmd), "'\(cmd)' contains a shell operator → must be unsafe")
        }
    }

    t.suite("CommandClassifier.isSafe — unknown / mutating commands are not safe") {
        for cmd in ["rm -rf /", "sudo reboot", "kill 1", "npm install",
                    "brew install wget", "git push", "mv a b", "chmod 777 x"] {
            t.expect(!CommandClassifier.isSafe(cmd), "'\(cmd)' should not be classified safe")
        }
    }

    t.suite("CommandClassifier.isSafe — prefix matching is precise") {
        t.expect(CommandClassifier.isSafe("ls"), "bare 'ls' is safe")
        t.expect(!CommandClassifier.isSafe("lsof"), "'lsof' must NOT match the 'ls' prefix")
        t.expect(!CommandClassifier.isSafe("grepx"), "'grepx' must NOT match the 'grep' prefix")
        t.expect(!CommandClassifier.isSafe(""), "empty string is not safe")
    }
}
