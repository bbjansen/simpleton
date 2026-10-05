import Foundation
import SimpletonCore

func runSpecWorkspaceChecks(_ t: TestRunner) async {
    t.suite("SpecArtifact file names") {
        t.expectEqual(SpecArtifact.plan.fileName, "plan.md", "plan file name")
        t.expectEqual(SpecArtifact.spec.fileName, "spec.md", "spec file name")
        t.expectEqual(SpecArtifact.brainstorm.fileName, "brainstorm.md", "brainstorm file name")
        t.expectEqual(SpecArtifact.board.fileName, "board.md", "board file name")
    }

    t.suite("SpecMode / SpecArtifact enumerate all cases") {
        t.expectEqual(SpecMode.allCases.count, 5, "brainstorm, spec, plan, act, board modes")
        t.expectEqual(SpecArtifact.allCases.count, 4, "four artifacts defined")
        t.expectEqual(SpecMode.plan.displayName, "Plan", "plan display name")
        t.expectEqual(SpecMode.brainstorm.displayName, "Brainstorm", "brainstorm display name")
        t.expectEqual(SpecMode.spec.displayName, "Spec", "spec display name")
        t.expectEqual(SpecMode.brainstorm.generatedArtifact, .brainstorm, "brainstorm generates brainstorm")
        t.expectEqual(SpecMode.spec.generatedArtifact, .spec, "spec generates spec")
        t.expect(SpecMode.act.generatedArtifact == nil, "act generates nothing")
        t.expectEqual(SpecMode.act.displayedArtifact, .plan, "act shows plan")
    }

    t.suite("SpecWorkspaceState JSON round-trip") {
        let original = SpecWorkspaceState(
            activeMode: .act, activeArtifact: .spec, projectPath: "/tmp/demo",
            updatedAt: Date(timeIntervalSince1970: 1000)
        )
        guard let data = try? JSONEncoder().encode(original),
            let decoded = try? JSONDecoder().decode(SpecWorkspaceState.self, from: data)
        else {
            t.expect(false, "encode/decode must not throw")
            return
        }
        t.expectEqual(decoded, original, "state survives JSON round-trip")
    }

    t.suite("SpecWorkspaceState defaults") {
        let state = SpecWorkspaceState()
        t.expectEqual(state.activeMode, .plan, "defaults to plan mode")
        t.expectEqual(state.activeArtifact, .plan, "defaults to plan artifact")
    }

    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("spec-workspace-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    await t.suite("SpecWorkspaceStore save + load round-trip (temp dir)") {
        let store = SpecWorkspaceStore(directory: dir)
        let state = SpecWorkspaceState(activeMode: .act, activeArtifact: .spec, projectPath: "/tmp/projA")
        await store.save(state)
        // A fresh store over the same directory must reload what was written.
        let reopened = SpecWorkspaceStore(directory: dir)
        let loaded = await reopened.state(for: "/tmp/projA")
        t.expectEqual(loaded.activeMode, .act, "mode reloaded from disk")
        t.expectEqual(loaded.activeArtifact, .spec, "artifact reloaded from disk")
        t.expectEqual(loaded.projectPath, "/tmp/projA", "project path reloaded")
    }

    await t.suite("SpecWorkspaceStore per-project isolation + default") {
        let store = SpecWorkspaceStore(directory: dir)
        let unknown = await store.state(for: "/tmp/never-saved")
        t.expectEqual(unknown.activeMode, .plan, "unknown project gets plan default")
        t.expectEqual(unknown.projectPath, "/tmp/never-saved", "default seeds the project path")
    }

    await t.suite("SpecWorkspaceStore artifact read/write under .plan/") {
        let projectRoot = dir.appendingPathComponent("repo").path
        let store = SpecWorkspaceStore(directory: dir)
        t.expectEqual(await store.readArtifact(.plan, projectRoot: projectRoot), "", "missing artifact reads empty")
        try? await store.writeArtifact(.plan, projectRoot: projectRoot, contents: "# Plan\n- [ ] task")
        let planURL = SpecWorkspaceStore.artifactURL(.plan, projectRoot: projectRoot)
        t.expect(FileManager.default.fileExists(atPath: planURL.path), ".plan/plan.md was created")
        t.expectEqual(
            await store.readArtifact(.plan, projectRoot: projectRoot), "# Plan\n- [ ] task", "artifact round-trips")
        t.expect(planURL.path.hasSuffix("/.plan/plan.md"), "artifact lives under .plan/")
    }
}
