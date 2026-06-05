import { createLightNode, WakuEvent, Protocols } from "@waku/sdk";
import type { IDecodedMessage } from "@waku/sdk";
import { program } from "commander";
import { EnrDecoder } from "@waku/enr";

const DEFAULT_NODE = "http://logos-delivery-simulator-nwaku-1:8645";

program
  .option("-t, --content-topic <string>", "Content topic", "my-ctopic")
  .option("-s, --shard-id <number>", "Shard ID", parseInt, 0)
  .option("-c, --cluster-id <number>", "Cluster ID", parseInt, 66)
  .option(
    "--single-node <string>",
    "example: http://logos-delivery-simulator-nwaku-1:8645",
  )
  .option(
    "--multiple-nodes <string>",
    "example: http://logos-delivery-simulator-nwaku-[1..10]:8645",
  )
  .parse(process.argv);

const {
  contentTopic: CONTENT_TOPIC,
  shardId: SHARD_ID,
  clusterId: CLUSTER_ID,
  singleNode: SINGLE_NODE,
  multipleNodes: MULTIPLE_NODES,
} = program.opts();

if (SINGLE_NODE && MULTIPLE_NODES) {
  console.error(
    "Error: --single-node and --multiple-nodes are mutually exclusive.",
  );
  process.exit(1);
}

// Expands "http://host-[1..5]:8645" → ["http://host-1:8645", ..., "http://host-5:8645"]
function expandNodePattern(pattern: string): string[] {
  const match = pattern.match(/^(.*)\[(\d+)\.\.(\d+)\](.*)$/);
  if (!match) return [pattern];

  const [, prefix, startStr, endStr, suffix] = match;
  const start = parseInt(startStr);
  const end = parseInt(endStr);

  return Array.from(
    { length: end - start + 1 },
    (_, i) => `${prefix}${start + i}${suffix}`,
  );
}

function resolveNodeUrls(): string[] {
  if (MULTIPLE_NODES) return expandNodePattern(MULTIPLE_NODES);
  return [SINGLE_NODE ?? DEFAULT_NODE];
}

async function enrToMultiaddrs(enrString: string): Promise<string[]> {
  try {
    const enr = await EnrDecoder.fromString(enrString);
    return enr.getFullMultiaddrs().map((addr) => addr.toString());
  } catch {
    return [];
  }
}

async function fetchBootstrapPeers(): Promise<string[]> {
  const nodeUrls = resolveNodeUrls();
  console.log(`Fetching peers from ${nodeUrls.length} node(s):`, nodeUrls);

  const results = await Promise.allSettled(
    nodeUrls.map(async (url) => {
      const res = await fetch(`${url}/info`);
      const { enrUri } = await res.json();
      return enrToMultiaddrs(enrUri);
    }),
  );

  const multiaddrs = results.flatMap((r) =>
    r.status === "fulfilled" ? r.value : [],
  );
  console.log("Bootstrap peers:", multiaddrs);
  return multiaddrs;
}

// Main

async function initLocalWakuClient() {
  const bootstrapPeers = await fetchBootstrapPeers();

  const node = await createLightNode({
    defaultBootstrap: false,
    bootstrapPeers,
    discovery: { peerExchange: true },
    libp2p: { filterMultiaddrs: false },
    networkConfig: { clusterId: CLUSTER_ID },
  });

  node.events.addEventListener(WakuEvent.Health, ({ detail }) =>
    console.log("Health:", detail),
  );

  await node.start();
  await node.waitForPeers([Protocols.LightPush, Protocols.Filter], 30_000);
  node.lightPush.start();

  const topicConfig = { contentTopic: CONTENT_TOPIC, shardId: SHARD_ID };
  const decoder = node.createDecoder(topicConfig);

  console.log("Subscribing to filter updates...");

  await node.filter.subscribe([decoder], (message: IDecodedMessage) => {
    if (message?.payload) {
      console.log("📩 Received message", {
        topic: message.contentTopic,
        size: message.payload.byteLength,
      });
    } else {
      console.warn("⚠️ Received empty message frame.");
    }
  });
}

initLocalWakuClient().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
