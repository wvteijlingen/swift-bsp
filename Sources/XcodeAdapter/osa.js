#!/usr/bin/osascript -l JavaScript
ObjC.import('Foundation');

function fail(message) {
  throw new Error(message);
}

function secondsSince(startMs) {
  return ((Date.now() - startMs) / 1000).toFixed(3);
}

function canonPath(inputPath) {
  if (!inputPath || inputPath.length === 0) fail('Path is empty.');
  var expanded = $(inputPath).stringByExpandingTildeInPath.js;
  var url = $.NSURL.fileURLWithPath(expanded).URLByResolvingSymlinksInPath;
  return url.path.stringByStandardizingPath.js;
}

function dirname(path) {
  return $(path).stringByDeletingLastPathComponent.js;
}

function hasSuffix(path, suffix) {
  var p = String(path);
  return p.slice(-suffix.length) === suffix;
}

function isSameOrDescendantPath(path, parent) {
  var p = String(path);
  var par = String(parent);
  if (p === par) return true;
  var normalizedParent = hasSuffix(par, '/') ? par : (par + '/');
  return p.indexOf(normalizedParent) === 0;
}

function pathExistsAsDirectory(path) {
  var isDirRef = Ref();
  var exists = $.NSFileManager.defaultManager.fileExistsAtPathIsDirectory(path, isDirRef);
  return Boolean(exists) && Boolean(isDirRef[0]);
}

function listNames(objects) {
  return objects.map(function (obj) { return obj.name(); }).join(', ');
}

function toText(value) {
  if (value === undefined || value === null) return '';
  return String(value);
}

function writeStdout(text) {
  if (!text || text.length === 0) return;
  var ns = $(text);
  var data = ns.dataUsingEncoding($.NSUTF8StringEncoding);
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
}

function waitUntilWorkspaceLoaded(workspaceDocument, timeoutSeconds) {
  var started = Date.now();
  while (!workspaceDocument.loaded()) {
    if ((Date.now() - started) > timeoutSeconds * 1000) {
      fail('Workspace did not finish loading within ' + timeoutSeconds + ' seconds.');
    }
    delay(0.2);
  }
}

function waitForWorkspaceDocumentToAppear(xcode, expectedPath, timeoutSeconds) {
  var started = Date.now();
  var expectedCanonical = canonPath(expectedPath);
  while (true) {
    var workspaces = xcode.workspaceDocuments();
    for (var i = 0; i < workspaces.length; i++) {
      var wsPath = workspaces[i].path();
      if (!wsPath) continue;
      if (canonPath(wsPath) === expectedCanonical) {
        return workspaces[i];
      }
    }
    if ((Date.now() - started) > timeoutSeconds * 1000) {
      fail('Opened document did not appear as a workspaceDocument within ' + timeoutSeconds + ' seconds.');
    }
    delay(0.2);
  }
}

function workspaceMatchesProjectDir(workspaceDocument, projectDir) {
  var wsPath = workspaceDocument.path();
  if (!wsPath) return false;

  var wsCanonical = canonPath(wsPath);
  var containerDir = dirname(wsCanonical);
  var isProjectBundle = hasSuffix(wsCanonical, '.xcodeproj') || hasSuffix(wsCanonical, '.xcworkspace');

  return (
    wsCanonical === projectDir ||
    containerDir === projectDir ||
    isSameOrDescendantPath(wsCanonical, projectDir) ||
    isSameOrDescendantPath(containerDir, projectDir) ||
    (isProjectBundle && isSameOrDescendantPath(containerDir, projectDir))
  );
}

function findWorkspaceForProjectDir(xcode, projectDir) {
  var workspaces = xcode.workspaceDocuments();
  if (workspaces.length === 0) fail('No open workspaceDocument found in Xcode.');

  var matches = [];
  for (var i = 0; i < workspaces.length; i++) {
    var ws = workspaces[i];
    if (workspaceMatchesProjectDir(ws, projectDir)) {
      matches.push(ws);
    }
  }

  if (matches.length === 0) {
    fail('No open workspaceDocument for project directory: ' + projectDir);
  }
  if (matches.length > 1) {
    fail('Multiple open workspaceDocuments matched project directory: ' + projectDir);
  }

  return matches[0];
}

function listProjectCandidates(projectDir) {
  var errorRef = Ref();
  var raw = $.NSFileManager.defaultManager.contentsOfDirectoryAtPathError(projectDir, errorRef);
  if (!raw) {
    fail('Failed to list directory: ' + projectDir);
  }

  var entries = ObjC.unwrap(raw);
  var workspaces = [];
  var projects = [];
  for (var i = 0; i < entries.length; i++) {
    var name = ObjC.unwrap(entries[i]);
    if (String(name).charAt(0) === '.') continue;
    if (hasSuffix(name, '.xcworkspace')) workspaces.push(projectDir + '/' + name);
    if (hasSuffix(name, '.xcodeproj')) projects.push(projectDir + '/' + name);
  }

  return { workspaces: workspaces, projects: projects };
}

function openCandidateWorkspaceOrProject(xcode, projectDir) {
  var candidates = listProjectCandidates(projectDir);
  var chosenPath;

  if (candidates.workspaces.length > 1) {
    fail('Multiple workspace candidates found: ' + candidates.workspaces.join(', '));
  }
  if (candidates.workspaces.length === 1) {
    chosenPath = candidates.workspaces[0];
  } else {
    if (candidates.projects.length > 1) {
      fail('Multiple project candidates found (and no workspace): ' + candidates.projects.join(', '));
    }
    if (candidates.projects.length === 0) {
      fail('No .xcworkspace or .xcodeproj found in: ' + projectDir);
    }
    chosenPath = candidates.projects[0];
  }

  xcode.open(Path(chosenPath));
  return waitForWorkspaceDocumentToAppear(xcode, chosenPath, 60);
}

function chooseByName(items, expectedName, itemLabel) {
  for (var i = 0; i < items.length; i++) {
    if (items[i].name() === expectedName) return items[i];
  }
  fail(
    itemLabel + " '" + expectedName + "' not found. Available " +
    itemLabel + 's: ' + listNames(items)
  );
}

function runDestinationDeviceIdentifier(runDestination) {
  try {
    var device = runDestination.device();
    if (!device) return '';
    return toText(device.deviceIdentifier());
  } catch (_) {
    return '';
  }
}

function canonicalIdentifier(value) {
  return String(value || '').trim().toLowerCase();
}

function looksLikeDeviceIdentifier(selector) {
  var s = String(selector || '').trim();
  if (s.length === 0) return false;
  if (s.indexOf('dvtdevice-') === 0) return true;
  if (/^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$/.test(s)) return true;
  if (/^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$/.test(s)) return true;
  if (/^[0-9A-Fa-f]{40}$/.test(s)) return true;
  return false;
}

function runDestinationMatches(runDestination, requestedSelector) {
  if (canonicalIdentifier(requestedSelector) === 'mac') {
    return toText(runDestination.platform()) === 'macosx';
  }
  if (looksLikeDeviceIdentifier(requestedSelector)) {
    return canonicalIdentifier(runDestinationDeviceIdentifier(runDestination)) === canonicalIdentifier(requestedSelector);
  }
  return toText(runDestination.name()) === requestedSelector;
}

function describeRunDestination(runDestination) {
  return (
    toText(runDestination.name()) +
    ' [platform=' + toText(runDestination.platform()) +
    ', deviceIdentifier=' + runDestinationDeviceIdentifier(runDestination) + ']'
  );
}

function chooseRunDestination(runDestinations, requestedSelector) {
  for (var i = 0; i < runDestinations.length; i++) {
    if (runDestinationMatches(runDestinations[i], requestedSelector)) {
      return runDestinations[i];
    }
  }

  var available = runDestinations.map(describeRunDestination).join(', ');
  fail(
    "run destination selector '" + requestedSelector + "' not found. " +
    "Use 'mac', a deviceIdentifier-looking selector, or an exact destination name. Available: " + available
  );
}

function waitForBuildResult(result, timeoutSeconds) {
  var started = Date.now();
  var emittedLength = 0;

  function emitNewBuildLog() {
    var fullLog = toText(result.buildLog());
    if (fullLog.length === 0) return;

    if (fullLog.length < emittedLength) {
      emittedLength = 0;
    }
    if (fullLog.length === emittedLength) return;

    var chunk = fullLog.slice(emittedLength);
    writeStdout(chunk);
    emittedLength = fullLog.length;
  }

  while (!result.completed()) {
    emitNewBuildLog();
    if ((Date.now() - started) > timeoutSeconds * 1000) {
      fail('Build timed out after ' + timeoutSeconds + ' seconds.');
    }
    delay(0.5);
  }
  emitNewBuildLog();

  var status = result.status();
  if (status !== 'succeeded') {
    var message = toText(result.errorMessage());
    throw new Error('Build finished with status: ' + status + (message ? ('. ' + message) : ''));
  }
}

function resolveXcodeApplication() {
  function appIfResolvable(target, resolvedPath) {
    try {
      var app = Application(target);
      app.running();
      return { app: app, appPath: resolvedPath || String(target) };
    } catch (_) {
      return null;
    }
  }

  var current = Application.currentApplication();
  current.includeStandardAdditions = true;

  try {
    var selectedDeveloperDir = String(current.doShellScript('/usr/bin/xcode-select -p')).trim();
    var developerSuffix = '/Contents/Developer';
    if (selectedDeveloperDir && hasSuffix(selectedDeveloperDir, developerSuffix)) {
      var appPath = selectedDeveloperDir.slice(0, selectedDeveloperDir.length - developerSuffix.length);
      if (hasSuffix(appPath, '.app') && $.NSFileManager.defaultManager.fileExistsAtPath(appPath)) {
        var selectedApp = appIfResolvable(appPath, appPath);
        if (selectedApp) return selectedApp;
      }
    }
  } catch (_) {}

  var byName = appIfResolvable('Xcode', '/Applications/Xcode.app');
  if (byName) return byName;

  var byID = appIfResolvable('com.apple.dt.Xcode', 'com.apple.dt.Xcode');
  if (byID) return byID;

  try {
    var appsDir = '/Applications';
    var entries = ObjC.unwrap($.NSFileManager.defaultManager.contentsOfDirectoryAtPathError(appsDir, null)) || [];
    for (var i = 0; i < entries.length; i++) {
      var entry = ObjC.unwrap(entries[i]);
      if (!hasSuffix(entry, '.app')) continue;
      var candidatePath = appsDir + '/' + entry;
      var bundle = $.NSBundle.bundleWithPath(candidatePath);
      if (!bundle) continue;
      if (toText(bundle.bundleIdentifier()) === 'com.apple.dt.Xcode') {
        var byPath = appIfResolvable(candidatePath, candidatePath);
        if (byPath) return byPath;
      }
    }
  } catch (_) {}

  fail("Could not resolve Xcode application. Install Xcode or set 'xcode-select -p' to an Xcode Developer directory.");
}

function run(argv) {
  var scriptStartMs = Date.now();

  if (argv.length !== 3) {
    fail('Usage: osascript -l JavaScript xcode_build.jxa <project_dir> <scheme_name> <run_destination_selector>');
  }

  var projectDir = canonPath(argv[0]);
  var schemeName = argv[1];
  var runDestinationSelector = argv[2];

  if (!pathExistsAsDirectory(projectDir)) {
    fail('Project directory does not exist or is not a directory: ' + projectDir);
  }

  var resolvedXcode = resolveXcodeApplication();
  var xcode = resolvedXcode.app;
  console.log('Building with ' + resolvedXcode.appPath);
  if (!xcode.running()) {
    xcode.launch();
  }

  var workspace = null;
  try {
    var activeWorkspace = xcode.activeWorkspaceDocument();
    if (activeWorkspace && workspaceMatchesProjectDir(activeWorkspace, projectDir)) {
      workspace = activeWorkspace;
    }
  } catch (e) {
    workspace = null;
  }

  if (!workspace) {
    try {
      workspace = findWorkspaceForProjectDir(xcode, projectDir);
    } catch (e2) {
      var message = String(e2);
      var noOpenWorkspaces = message.indexOf('No open workspaceDocument found in Xcode.') !== -1;
      var noMatchingWorkspace = message.indexOf('No open workspaceDocument for project directory:') !== -1;
      if (!noOpenWorkspaces && !noMatchingWorkspace) {
        throw e2;
      }
      workspace = openCandidateWorkspaceOrProject(xcode, projectDir);
    }
  }

  waitUntilWorkspaceLoaded(workspace, 60);

  var activeSchemeName = '';
  var activeRunDestinationMatchesSelector = false;
  try {
    activeSchemeName = toText(workspace.activeScheme().name());
  } catch (_) {
    activeSchemeName = '';
  }
  try {
    var activeRunDestination = workspace.activeRunDestination();
    activeRunDestinationMatchesSelector = Boolean(activeRunDestination) &&
      runDestinationMatches(activeRunDestination, runDestinationSelector);
  } catch (_) {
    activeRunDestinationMatchesSelector = false;
  }

  if (activeSchemeName !== schemeName) {
    var schemes = workspace.schemes();
    if (schemes.length === 0) fail('No schemes available in workspace.');
    workspace.activeScheme = chooseByName(schemes, schemeName, 'scheme');
  }

  if (!activeRunDestinationMatchesSelector) {
    var runDestinations = workspace.runDestinations();
    if (runDestinations.length === 0) fail('No run destinations available in workspace.');
    workspace.activeRunDestination = chooseRunDestination(runDestinations, runDestinationSelector);
  }

  // console.log('ready_to_build_seconds=' + secondsSince(scriptStartMs));

  var buildResult = workspace.build();
  waitForBuildResult(buildResult, 3600);

  return 'Build succeeded for scheme ' + schemeName + ' using run destination selector ' + runDestinationSelector + '.';
}