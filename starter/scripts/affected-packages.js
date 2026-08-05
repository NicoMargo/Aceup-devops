#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, ".."); // starter/
const WORKSPACE_GROUPS = ["packages", "services"];

function listWorkspaces() {
const workspaces = [];
for (const group of WORKSPACE_GROUPS) {
    const groupDir = path.join(ROOT, group);
    if (!fs.existsSync(groupDir)) continue;
    for (const name of fs.readdirSync(groupDir)) {
    const dir = path.join(groupDir, name);
    const pkgJsonPath = path.join(dir, "package.json");
    if (fs.statSync(dir).isDirectory() && fs.existsSync(pkgJsonPath)) {
        const pkg = JSON.parse(fs.readFileSync(pkgJsonPath, "utf8"));
        workspaces.push({
        name: pkg.name,
        dir: path.relative(ROOT, dir).split(path.sep).join("/"), // "packages/logger"
        deps: Object.keys(pkg.dependencies ?? {}).filter((d) => d.startsWith("@aceup/")),
        isService: group === "services",
        });
    }
    }
}
return workspaces; 
}

function buildDependentsGraph(workspaces) {
const dependents = new Map(workspaces.map((w) => [w.name, []]));
for (const w of workspaces) {
    for (const dep of w.deps) {
    dependents.get(dep)?.push(w.name);
    }
}
return dependents;
} 

function ownerOf(fileRelativeToStarter, workspaces) {
const matches = workspaces.filter(
    (w) => fileRelativeToStarter === w.dir || fileRelativeToStarter.startsWith(w.dir + "/")
);
matches.sort((a, b) => b.dir.length - a.dir.length); // longest prefix wins
return matches[0] ?? null;
}

function computeAffected(changedFilesFromRepoRoot, workspaces) {
const dependents = buildDependentsGraph(workspaces);
const directlyChanged = new Set();
let rootChange = false;

for (const file of changedFilesFromRepoRoot) {
      if (!file.startsWith("starter/")) {
        rootChange = true; // change outside the monorepo root (e.g. CI workflow) — safer to rebuild everything
        continue;
      }
    const relative = file.slice("starter/".length);
    const owner = ownerOf(relative, workspaces);
    if (owner) {
    directlyChanged.add(owner.name);
    } else {
    rootChange = true; // inside starter/, but not owned by any workspace
    }
}

if (rootChange) {
    return { rootChange: true, affected: workspaces.map((w) => w.name) };
}

const affected = new Set(directlyChanged);
const stack = [...directlyChanged]; 
while (stack.length > 0) {
    const current = stack.pop();
    for (const dependent of dependents.get(current) ?? []) {
    if (!affected.has(dependent)) {
        affected.add(dependent);
        stack.push(dependent);
    }
    }
}
return { rootChange: false, affected: [...affected] };
} 

function main() {
const changedFiles = process.argv.slice(2).filter(Boolean);
if (changedFiles.length === 0) {
    console.error("Usage: node affected-packages.cjs <file1> <file2> ...");
    process.exit(1);
}

const workspaces = listWorkspaces();
const byName = new Map(workspaces.map((w) => [w.name, w]));
const result = computeAffected(changedFiles, workspaces);

const affectedServices = result.affected
    .map((name) => byName.get(name))
    .filter((w) => w?.isService)
    .map((w) => w.name);

console.log(JSON.stringify({
    rootChange: result.rootChange,
    affectedPackages: result.affected,
    affectedServices,
}, null, 2));
} 

main();
