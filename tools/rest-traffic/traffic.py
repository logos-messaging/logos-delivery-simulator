import requests
import time
import os
import base64
import urllib.parse
import argparse
import re
import logging

logging.basicConfig(level=logging.INFO, format='[%(asctime)s.%(msecs)03d] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

def send_waku_msg(node_address, kbytes, pubsub_topic, content_topic):
    # TODO dirty trick .replace("=", "")
    base64_payload = (base64.b64encode(os.urandom(kbytes*1000)).decode('ascii')).replace("=", "")
    logging.info("size message kBytes %.3f KBytes", len(base64_payload) *(3/4)/1000)
    body = {
        "payload": base64_payload,
        "contentTopic": content_topic,
        "version": 1,  # You can adjust the version as needed
        "timestamp": int(time.time() * 1_000_000_000) # use nanoseconds to match nwaku node time unit
    }

    encoded_pubsub_topic = urllib.parse.quote(pubsub_topic, safe='')

    url = f"{node_address}/relay/v1/messages/{encoded_pubsub_topic}"
    headers = {'content-type': 'application/json'}

    logging.info('Waku REST API: %s PubSubTopic: %s, ContentTopic: %s', url, pubsub_topic, content_topic)
    s_time = time.time()
    
    response = None
    try:
      logging.info('Sending request')
      response = requests.post(url, json=body, headers=headers)
    except Exception as e:
      logging.error("Error sending request: %s", e)

    if(response != None):
      elapsed_ms = (time.time() - s_time) * 1000
      logging.info('Response from %s: status:%s content:%s [%.4f ms.]', node_address, 
        response.status_code, response.text, elapsed_ms)

parser = argparse.ArgumentParser(description='')

# these flags are mutually exclusive, one or the other, never at once
group = parser.add_mutually_exclusive_group(required=True)
group.add_argument('-sn', '--single-node', type=str, help='example: http://logos-delivery-simulator_nwaku_1:8645')
group.add_argument('-mn', '--multiple-nodes', type=str, help='example: http://logos-delivery-simulator_nwaku_[1..10]:8645')

# rest of araguments
parser.add_argument('-c', '--content-topic', type=str, help='content topic', default="my-ctopic")
parser.add_argument('-p', '--pubsub-topic', type=str, help='pubsub topic', default="/waku/2/rs/66/0")
parser.add_argument('-s', '--msg-size-kbytes', type=int, help='message size in kBytes', default=10)
parser.add_argument('-d', '--delay-seconds', type=int, help='delay in seconds between messages', default=15)
args = parser.parse_args()

logging.info("Arguments: %s", args)

if args.single_node != None:
  logging.info("Injecting traffic to single node REST API: %s", args.single_node)

# this simply converts from http://url_[1..5]:port to
# [http://url_1:port or from http://url-[1..5]:port to
# [http://url-1:port
nodes = []
if args.multiple_nodes:
  start, end = (int(x) for x in re.search(r"\[(\d+)\.\.(\d+)\]", args.multiple_nodes).groups()) 
 
  if start is None or end is None:
      logging.error("Could not parse range of multiple_nodes argument")
      exit

  logging.info("Injecting traffic to multiple nodes REST APIs") 
  for i in range(end, start - 1, -1): 
    nodes.append(re.sub(r"\[\d+\.\.\d+\]", str(i), args.multiple_nodes))

for node in nodes:
  logging.info("Node: %s", node)


while True:
    # calls are blocking
    # limited by the time it takes the REST API to reply
    send_start_time = time.time()
    if args.single_node != None:
      send_waku_msg(args.single_node, args.msg_size_kbytes, args.pubsub_topic, args.content_topic)

    if args.multiple_nodes != None:
      for node in nodes:
        send_waku_msg(node, args.msg_size_kbytes, args.pubsub_topic, args.content_topic)

    send_elapsed = time.time() - send_start_time
    if args.multiple_nodes != None:
      logging.info("Time taken to send to all nodes: %.4f seconds", send_elapsed)
    else:
      logging.info("Time taken to send to single node: %.4f seconds", send_elapsed)

    time_to_sleep = args.delay_seconds - send_elapsed
    if time_to_sleep > 0:
      logging.info("Sleeping %.4f seconds to maintain delay of %d seconds between rounds", time_to_sleep, args.delay_seconds)
    else:
      logging.info("No sleep needed to maintain delay of %d seconds between rounds", args.delay_seconds)

    time.sleep(max(0, time_to_sleep))