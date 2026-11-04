<!--
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# DOOP key/value source receipt

CopyOnWriteIdentityMap stores one immutable parallel key/value generation. Public Entries are fresh immutable identity projections; forEach traverses the captured arrays and preserves subclass dispatch.

Canonical recipe and qualification: [Synexia commit cfa05713fe53](https://github.com/hsoliwal/com.synexia/commit/cfa05713fe5395694af36df74373dcfe1e7e9031).

Receiving parent: `cf69a894b8ee6b25921943b4280107584a91ab7e`. Canonical datasets: `doop-key-value-equinox-20261102`. All Java files below are actual verified SDK Result outputs.

## Executed verification

17/17 JIT/interpreter tests including actual synchronous/asynchronous ListenerQueue integration. Java 8 production andJava 17 test compatibility passed. At 4,096 mappings structural storage fell from 4,098 objects/114,720 bytes to 4 objects/32,840 bytes. Exact five-source eventmgr closure and original test match the tested default revision.

## Exact output blobs

| Path | Git blob |
|---|---|
| `bundles/org.eclipse.osgi.tests/src/org/eclipse/osgi/tests/eventmgr/CopyOnWriteIdentityMapArrayTests.java` | `280930bfa0a0d6422311816baabe80a639394d27` |
| `bundles/org.eclipse.osgi/supplement/src/org/eclipse/osgi/framework/eventmgr/CopyOnWriteIdentityMap.java` | `11db1e75e4ab8cba1c4aa7fb6f93ae1b6c421f77` |

## Acceptance scope

Full Tycho/OSGi acceptance remains unexecuted. Empty/singleton footprints grow; append/removal copies two lanes. Existing upstream commits remain on this branch.

The existing broader branch acceptance gates remain in force. This receipt does not claim whole-repository or fleet-wide conversion, universal throughput gains, or default-branch integration.
