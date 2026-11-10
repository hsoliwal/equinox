# Release readiness for M3JDK21 (Java 21): equinox

Measured on 2026-11-09 against fork master `ad07c8a70da67dda6b09847de4f77781a5d80aed` (upstream master `a8546aec0035`).
Tools and raw evidence: [`docs/m3/jdk21/release-20261109`](../jdk21/release-20261109/). Every gate ran locally on CPU; fork CI runs are not counted
(startup failures and queue starvation on this account, 2026-11).

| # | Gate | Verdict | Evidence |
| --- | --- | --- | --- |
| G1 | No Java 22+ requirement on master: BREE above JavaSE-21 (0), build/IDE pins above 21 (1), unnamed `_` (0), `import module` (0) | FAIL on master (fixed by RECIPE_CHANGES.tsv in this PR: 1 files) | CENSUS.tsv (code view; hits inside strings, text blocks and comments: CENSUS_MASKED.tsv) |
| G2 | Java-21 compile gate: JDK 25 javac `--release 21` minus `--release 25` over 2 bundles (17 files, 2 roots); 0 baseline rows cancel | FAIL on master (residue 175, GATE_RESIDUE_MASTER.tsv); PASS with this PR (residue 0) | GATE_RESIDUE.tsv, GATE_SUMMARY.tsv |
| G2b | Parse gate: every tracked Java source (2074 files, test bundles included, test-input folders excluded), JDK 25 javac `--release 21` stopped after parsing | PASS | PARSE_GATE.tsv |
| G3 | Recipe fixed point (`apply_jdk21.sh` + `apply_jdk21_pins.sh` change nothing on master) | FIXED in this PR (1 files) | RECIPE_CHANGES.tsv |
| G4 | Metadata consistent: Tycho bundle/feature versions match their pom, no EE above 21 in a Java-21 bundle | PASS | META.tsv |
| G5 | Full Tycho build of this repository on JDK 21 (`mvn -B clean verify -DskipTests`, fork parent + SDK target from the fork aggregator, other components from the upstream 4.42 I-build repository) | PASS | BUILD SUCCESS in 128 s, modules 71/71 ok, 0 failed, 0 [ERROR] rows (BUILD_G5.tsv, BUILD_G5_ERRORS.tsv, BUILD_G5.log.gz) |
| G6 | Eclipse SDK product build and launch on JDK 21 | PENDING | aggregator verdict, eclipse.platform.releng.aggregator docs/m3/release/RELEASE_READINESS.md |

## What this PR changes

Fork master `ad07c8a70da6` lowered `org.eclipse.equinox.security.linux` to JavaSE-21 in its metadata (2026-10-20 compat
pass), but the sources are the java.lang.foreign (FFM) version of upstream fff3578521 ("Replace JNA with java.lang.foreign
in equinox.security.linux"; FFM is final only in Java 22, preview in 21). `--release 21` rejects them: 175 errors
(GATE_RESIDUE_MASTER.tsv). The 2026-10-20 gate ran only on the fork's Java-25 code bundles and missed this
metadata-only bundle.

Fill (`fill_ffm_to_jna.sh`, the same leaf as the eclipse.platform org.eclipse.core.filesystem JNA fill), no tracked file deleted:

| Step | Files |
| --- | --- |
| Java files the FFM commit modified or removed come back byte for byte from its upstream parent c8f78f33e5 (JNA) | GError, LinuxPasswordProvider, SecretSchema (restored); GList, SecretSchemaAttribute, SecretSchemaAttributeType (re-added) |
| Java files the FFM commit added stay tracked but leave the build | Foreign, LibGio, LibSecret: `tycho-compiler-plugin` `<excludes>` in pom.xml, `excluding=` on the `src/` entry of .classpath |
| MANIFEST.MF gets back `Require-Bundle: com.sun.jna;bundle-version="[5.8.0,6.0.0)"` | com.sun.jna 5.19.1 is in eclipse-sdk-prereqs.target (fork and upstream) |
| Recipe: `bundles/org.eclipse.equinox.spi.tests/.classpath` JRE container JavaSE-25 becomes JavaSE-21 | RECIPE_CHANGES.tsv |

Bundle-Version stays 1.2.0.qualifier (never backwards). Gate after the fill: 17 files, 0 errors, residue 0.

## HOLD (user action)

1. Done 2026-11-10 (user-approved, branch `m3/jdk21-ffm-cleanup-20261110`): Foreign.java, LibGio.java and LibSecret.java
   deleted and their Tycho `<excludes>` / `.classpath` `excluding=` removed. The bundle's Java sources are now byte for byte
   those of upstream c8f78f33e5 (parent of the FFM commit fff3578521); only BREE/compliance (21) and the version (1.2.0)
   differ. The FFM originals stay reachable in history (upstream fff3578521, fork master 7ed67c081fca).
   Gates on that branch: Java-21 residue 0 (11 files), parse 0 (2071 files), metadata 0 rows, ECJ pre-check 0 rows,
   Tycho build on JDK 21.0.9 BUILD SUCCESS 71/71 in 361 s.
2. Runtime check of the Linux secure-storage provider (libsecret over JNA) on a Linux desktop with JDK 21: not run here.

## G5 (Tycho build on JDK 21.0.9)

| Attempt | Result |
| --- | --- |
| 1 | BUILD FAILURE: 69/70 modules ok; org.eclipse.equinox.executable needs the launcher natives of equinox.binaries (`equinox.binaries.loc`, default `../equinox.binaries` next to this repository, as in the aggregator); environment, not code |
| 2 | BUILD SUCCESS: 71/71 modules in 128 s, with eclipse-equinox/equinox.binaries at the aggregator gitlink 7a1125f75ed9 checked out next to the clone. org.eclipse.equinox.security.linux compiles on JDK 21 with the JNA sources; the three excluded FFM sources stay out of the ECJ build (Tycho `excludes`) |

## Re-run

```bash
git clone --depth 1 https://github.com/hsoliwal/equinox.git && git -C equinox remote add upstream <upstream>
git -C equinox fetch --depth 1 --filter=blob:none upstream master:refs/remotes/upstream/master
bash docs/m3/jdk21/release-20261109/gate_master.sh equinox    # paths at the top of the script; JAVAC = JDK 25 javac
bash docs/m3/jdk21/release-20261109/meta_check.sh equinox > META.tsv
```

The gate compiles every bundle that upstream master declares JavaSE-22 or newer, plus the 2026-10-20 list, against the
newest jar of every bundle in a p2 pool. Errors in both runs are classpath noise (APIs newer than the pool); what remains
after `--release 21` is the Java 22+ residue and must be empty.
