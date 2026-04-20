#!/usr/bin/env node
/**
 * Babysitter plugin entry point for OpenCode.
 *
 * OpenCode discovers plugins by looking for JS/TS modules in
 * .opencode/plugins/. This file registers the babysitter hooks
 * with the OpenCode plugin system.
 */

"use strict";

const path = require("path");

const PLUGIN_DIR = __dirname;

module.exports = {
  name: "babysitter",
  version: require(path.join(PLUGIN_DIR, "plugin.json")).version,

  hooks: {
    "session.created": require(path.join(PLUGIN_DIR, "hooks", "session-created.js")),
    "session.idle": require(path.join(PLUGIN_DIR, "hooks", "session-idle.js")),
    "shell.env": require(path.join(PLUGIN_DIR, "hooks", "shell-env.js")),
    "tool.execute.before": require(path.join(PLUGIN_DIR, "hooks", "tool-execute-before.js")),
    "tool.execute.after": require(path.join(PLUGIN_DIR, "hooks", "tool-execute-after.js")),
  },
};
