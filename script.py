import asyncio
import json
import os
import random
import requests
from playwright.async_api import async_playwright

# ==============================
# LOAD CONFIG
# ==============================
with open("config.json", "r") as f:
    config = json.load(f)

WEBHOOK_URL = config.get("WEBHOOK_URL")
DISCORD_CHANNEL_URL = config.get("DISCORD_CHANNEL_URL")
STATE_FILE = config.get("STATE_FILE", "discord_state.json")
OWNER_ID = config.get("OWNER_ID")
HEADLESS = config.get("HEADLESS", False)
ROLE_PING_ENABLED = config.get("ROLE_PING_ENABLED", False)
TIMER_SECONDS = config.get("TIMER_SECONDS", 630)
ROLE_PINGS = {
    "Epic": config.get("ROLE_PINGS_EPIC"),
    "Legendary": config.get("ROLE_PINGS_LEGENDARY"),
}

timer_counter = TIMER_SECONDS

# === STYLE CONFIG (adapted from Lua) ((dont change pls)) ===
FOOTER_TEXT = "brought to you by arle."
FOOTER_ICON = "https://i.imgur.com/JdlwG9w.jpeg"

COLORS = {
    "Legendary": 0xd09c17,
    "Epic": 0xbf1ec8,
    "Rare": 0x3158a8,
    "Common": 0x5ac73c
}

RARITY_ORDER = ["Legendary", "Epic", "Rare", "Common"]
RARITY_PRIORITY = {
    "Legendary": 4,
    "Epic": 3,
    "Rare": 2,
    "Common": 1
}

async def send_payload(payload):
    try:
        response = requests.post(WEBHOOK_URL, json=payload)
        print(f"[Webhook] Status: {response.status_code}")
    except Exception as e:
        print(f"[Webhook Error] {e}")


def parse_counts_from_text(boxes_text: str):
    counts = {"Legendary": 0, "Epic": 0, "Rare": 0, "Common": 0}
    for line in boxes_text.splitlines():
        for rarity in counts.keys():
            if rarity in line:
                num_part = line.split("x")[-1].strip()
                try:
                    counts[rarity] = int(num_part)
                except ValueError:
                    counts[rarity] = 0
    return counts


def build_payload_from_counts(counts: dict):
    lines = []
    rarities_found = []
    highest = "Common"
    for r in RARITY_ORDER:
        c = int(counts.get(r, 0))
        if c > 0:
            lines.append(f"{r} Box x{c}")
            rarities_found.append(r)
            if RARITY_PRIORITY[r] > RARITY_PRIORITY[highest]:
                highest = r

    mentions = []
    allowed_roles = []
    if ROLE_PING_ENABLED:
        for r in rarities_found:
            role_id = ROLE_PINGS.get(r)
            if role_id:
                mentions.append(f"<@&{role_id}>")
                allowed_roles.append(role_id)

    description = "\n".join(lines) if lines else "No stock"

    embed = {
        "title": "EVENT BOX STOCK",
        "description": description,
        "color": COLORS.get(highest, COLORS["Common"]),
        "footer": {"text": FOOTER_TEXT, "icon_url": FOOTER_ICON},
    }

    payload = {
        "username": "Arlecchino",
        "content": " ".join(mentions) if mentions else "",
        "embeds": [embed],
    }
    if allowed_roles:
        payload["allowed_mentions"] = {"roles": allowed_roles}
    return payload, rarities_found


async def extract_boxes_text(embed):
    fields = await embed.query_selector_all(".embedField__623de")
    boxes_text = ""
    for field in fields:
        name_el = await field.query_selector(".embedFieldName__623de")
        value_el = await field.query_selector(".embedFieldValue__623de")
        name = await name_el.inner_text() if name_el else ""
        value = await value_el.inner_text() if value_el else ""
        if "Boxes" in name:
            boxes_text = value
    return boxes_text


async def send_critical_alert():
    payload = {
        "username": "Arlecchino",
        "content": f"<@{OWNER_ID}>",
        "embeds": [
            {
                "title": "SOMETHING HAS GONE TERRIBLY WRONG!",
                "description": "The main bot is dead, or a critical error occurred.",
                "color": 0xff0000,
                "footer": {"text": FOOTER_TEXT, "icon_url": FOOTER_ICON},
            }
        ]
    }
    await send_payload(payload)
    print("[ALERT] Critical alert webhook sent!")


async def watchdog_timer():
    global timer_counter
    while True:
        await asyncio.sleep(1)
        timer_counter -= 1
        if timer_counter <= 0:
            await send_critical_alert()
            timer_counter = TIMER_SECONDS  # reset after sending


async def run():
    global timer_counter
    print("[+] Starting bot...")
    async with async_playwright() as p:
        print("[+] Launching Chromium...")
        browser = await p.chromium.launch(headless=HEADLESS, args=[
            "--disable-blink-features=AutomationControlled"
        ])
        context = await browser.new_context(
            viewport={"width": 1280, "height": 720},
            storage_state=STATE_FILE if os.path.exists(STATE_FILE) else None
        )

        # Remove webdriver flag
        await context.add_init_script("""
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
        """)

        # Manual login if no state
        if not os.path.exists(STATE_FILE):
            print("[+] No saved state found. Logging in manually...")
            page = await context.new_page()
            await page.goto("https://discord.com/login")
            print("[!] Please login manually. Press ENTER when done.")
            input()
            await context.storage_state(path=STATE_FILE)
            print("[+] Login state saved.")
            await page.close()

        page = await context.new_page()
        await page.goto(DISCORD_CHANNEL_URL)
        print(f"[+] Opened channel: {DISCORD_CHANNEL_URL}")

        last_message_id = None
        scroll_counter = 0

        # Start watchdog timer
        watchdog_task = asyncio.create_task(watchdog_timer())

        try:
            while True:
                try:
                    await page.wait_for_selector('div[role="listitem"]', timeout=10000)
                    messages = await page.query_selector_all('div[role="article"]')

                    if messages:
                        last_message = messages[-1]
                        msg_id = await last_message.get_attribute("data-list-item-id")

                        if msg_id != last_message_id:
                            username_span = await last_message.query_selector("span.username_c19a55")
                            bot_tag = await last_message.query_selector(".botTag__82f07")
                            embed = await last_message.query_selector(".embedFull__623de")

                            if bot_tag and embed:
                                username = await username_span.inner_text() if username_span else "Unknown"
                                print(f"[Webhook Detected] {username}")

                                boxes_text = await extract_boxes_text(embed)
                                if boxes_text:
                                    counts = parse_counts_from_text(boxes_text)
                                    payload, rarities_found = build_payload_from_counts(counts)

                                    if counts.get("Epic", 0) > 0 or counts.get("Legendary", 0) > 0:
                                        await send_payload(payload)
                                        print(f"[+] Posted: {payload['embeds'][0]['description'].replace(chr(10),' | ')}")
                                    else:
                                        print("[Skipped] No Epic or Legendary boxes found.")

                                # Reset timer on new message
                                timer_counter = TIMER_SECONDS
                                print("[Timer Reset] New message detected.")

                                last_message_id = msg_id

                    # Randomize wait to mimic human
                    wait_time = random.uniform(2.5, 7)
                    await asyncio.sleep(wait_time)

                    scroll_counter += 1
                    if scroll_counter % random.randint(10, 20) == 0:
                        await page.mouse.wheel(0, random.randint(100, 400))
                        print("[+] Scrolled to mimic human activity.")

                except Exception as e:
                    print(f"[Error] {e}. Retrying in 10 seconds...")
                    await asyncio.sleep(10)

        finally:
            print("[-] Cleaning up...")
            watchdog_task.cancel()
            await browser.close()


if __name__ == "__main__":
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        print("[-] Script stopped by user.")
