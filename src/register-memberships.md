# Register memberships

> **Protocol exercised:** RLN membership registration — bulk-registers RLN memberships against the on-chain RLN contract that the simulator deploys, so you can stress how the [logos-delivery](https://github.com/logos-messaging/logos-delivery) nodes pick up new memberships in real time.

The [go-waku-light](https://github.com/alrevuelta/go-waku-light) tool can be used as well to register multiple RLN memberships. This can be useful to stress test the nodes, forcing a large amount of memberships. Set `amount` to the amount of memberships that you want to register. Note that it takes some time, since memberships are registered one after the other. You can spin up multiple services like this, but in that case you must provide different `priv-key` to each. Note that these memberships are essentially throwaway — they are not used to send messages.

```jsx
docker run --network logos-delivery-simulator_simulation alrevuelta/go-waku-light:07b8f32 \
--eth-endpoint=http://foundry:8545 \
--contract-address=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 \
register \
--priv-key=ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
--user-message-limit=1 \
--amount=100

```

The foundry service in the logos-delivery-simulator generates deterministic accounts that can be used to register memberships. It is recommended to use different accounts for registering multiple memberships at the same time. The last 20 accounts generated are provided for ad-hoc testing purposes.

<details>
  <summary>Account and Private-key Pairs</summary>
  
  #### Account Addresses
  499. 0x87d60ca295c702c03e65ce658a304c729f4d230c
  500. 0x42cbc74d159f243faa636759ded727ae3b1d9471
  501. 0x9e7ef0f7b0ae2da4a38ea10e20a381d89dcdf957
  502. 0xf6b5275d86f3116a5e99a57811c91261e2c1de28
  503. 0xd35f88407a7de00ad1420777c1fd6e90c60091c5
  504. 0xcd1bfae32108b6a2ca567a6c6e161690e578fb8d
  505. 0x318733b740a03619452ef79f39d6e329703c0573
  506. 0xf7ef0506e7d3167986ed0370e10a5769641bfd20
  507. 0x2c8ab749e426bc4652b02b3e217a87d7b5951a6a
  508. 0x281361736c998af5e1812e1a6500418526501c81
  509. 0xce4f66d4b514fda7238a45deea74a0bbfab1682c
  510. 0x71ea5563241e088ee9d2991c2963ecb655fac63c
  511. 0xcacdfa6104c7219a69978f2c7d4bd133b9b12945
  512. 0x1afa0189a8f3db73edd9955a048d1eda6fbc5359
  513. 0x4976d35e4c913f35d0ea8aca0e813c0f50171eac
  514. 0x7fb487fe725208d1c00c3bfef8b58e84c2262e0f
  515. 0x39c0e568bf0dd3b6e247ce29feca95b1a371da25
  516. 0xa54faa3e1ef5da5b2a4cc9538da09321ee49986c
  517. 0x28b1ffd61201495d23b249f38dc44b092600fd43
  518. 0xa58f61a4e1f9d266a3423fc1e1092e3d825b60a0
  519. 0x2d7ab1c0b01238fb1e48058caf5077788d5ee8e8
  
  #### Private-keys
  499. 0x5164f55d68dfea715364e74f2c6369af04239405832cf768010f5970ed8af919
  500. 0xf3be0661f9fa90d191f2058ffd04e63eec1ccf2de44faef10b32c7b182a077d5
  501. 0x13dfbe4eb50090c96c89b0febd3f1889323391ffba3d0e576a62e0c9181724b7
  502. 0xe277568c674f02e06687aeddd3f16c8d530b9e7310e8c2606f14c7d8f8722373
  503. 0x8c893c7a2402f58f5c8ce60457342b3b047512f4051460ab6eb244956753d542
  504. 0x0178b1c2b78a1edb55566bef4de594cf6f72b85bc22ac8755375006c636684c8
  505. 0xc4a37ad6735eb28be9aaaf0f4827956bdf601ad21e1ce0aef2498fce1113c14d
  506. 0x48f0ff5d2ff7cdad1a2be4e0fbfc85b0ecad67a529c5dbab35999c50e67b052f
  507. 0xa68456078297c2c58facca3ff8e42413b9a7bca2f116e9e24dac2dbeed9657b1
  508. 0xd0d69614e987efdb7f6d16cdc03eb3f8c1a494f5e47ad81c03a42a5e08479898
  509. 0x78d2374248bc4aeb4e1d05c6675f469e9e12ebbc9baa89e6aba0b36fd896f83b
  510. 0x34857abc26826772bd8a717a5c7a47226b4cab6ab2058af07e59f4cc13183924
  511. 0x3ed39f39efea7c7fcf5f10c4225fa7065d78d8306ac91d51c1a590aff18a2c93
  512. 0xbb6e7fbd8be4b2e7137fc1651fd4671e78ca7cee56597a201ffd139b12c395fe
  513. 0xfc7de77367c72aac38e2ec9a538101bdc94a147d9f101f004b3a3d6da11cdf87
  514. 0xd6aee4f69bcefa0a300977cb735b6b9a908d5a9bd6768693e11b57fe673a621a
  515. 0x8ff7c8d7e263a391bfcd56b6f46ddade81cc1c8a6036ef32fb02d73a9e344fab
  516. 0x686001b3fd9042ca3416efa2cc03357a9862d46c4672f83b8bc905701066a5db
  517. 0x089710323628168e28b092884ba0d193b4300531db2eaab6ad206867b3a7106e
  518. 0xd9faa2479f84917759e79ef2e1858e48ceb1117d586703c3595ff60702054025
  519. 0xb4b3cfbe261c743eade34fccbf61a9dd09770e55ecd56c31d1a00a924d747e2a
</details>

🎯**Goals**:

- Tests how the network reacts to a massive amount of memberships.
- Tests that nodes pick-up new memberships in real time and match.

👀**Observability**:

- Check the RLN memberships being registered in the block explorer `localhost:3000`.
- Check in grafana `localhost:3001` the metric “RLN Registered Memberships” and verify the nodes are picking up the new registrations.

