// Sources/Simpleton/Resources/panel-bridge.js
// Injected into every JS panel WebView at document start.
// Provides window.terminal and window.storage APIs backed by Swift message handlers.

(function () {
    "use strict";

    // Internal: send a message to Swift and return a Promise that resolves with the reply
    function callBridge(handlerName, body) {
        return new Promise(function (resolve) {
            var id = Math.random().toString(36).slice(2);
            window["__bridge_" + id] = resolve;
            webkit.messageHandlers[handlerName].postMessage({ body: body, callbackId: id });
        });
    }

    window.terminal = {
        /** Insert a command into the focused terminal pane */
        insert: function (cmd) {
            webkit.messageHandlers.insert.postMessage(cmd);
        },
        /** Returns Promise<string[]> — last n lines from the terminal buffer */
        getOutput: function (n) {
            return callBridge("getOutput", n === undefined ? 50 : n);
        },
        /** Returns Promise<string> — current working directory of the focused pane */
        getCwd: function () {
            return callBridge("getCwd", null);
        },
        /** Returns Promise<string> — current text selection in the terminal */
        getSelection: function () {
            return callBridge("getSelection", null);
        },
        /** Subscribe to terminal output lines. cb(lines: string[]) called on each new output. */
        onOutput: function (cb) {
            window.__outputCb = cb;
            webkit.messageHandlers.onOutput.postMessage(null);
        },
        /** Unsubscribe from terminal output */
        offOutput: function () {
            window.__outputCb = null;
            webkit.messageHandlers.offOutput.postMessage(null);
        },
    };

    window.storage = {
        /** Returns Promise<any> — stored value for key, or null if not set */
        get: function (key) {
            return callBridge("storageGet", key);
        },
        /** Set a value for key (fire-and-forget) */
        set: function (key, value) {
            webkit.messageHandlers.storageSet.postMessage({ key: key, value: value });
        },
        /** Returns Promise<object> — all stored key/value pairs */
        getAll: function () {
            return callBridge("storageGetAll", null);
        },
    };

    // Called by Swift bridge to deliver batched output lines to the subscriber
    window.__deliverOutput = function (lines) {
        if (window.__outputCb) window.__outputCb(lines);
    };

    // Called by Swift bridge to resolve a pending promise
    window.__resolveCallback = function (id, value) {
        var fn = window["__bridge_" + id];
        if (fn) { fn(value); delete window["__bridge_" + id]; }
    };
}());
