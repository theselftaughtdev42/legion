import asyncio
from microsandbox import Sandbox

async def main():
    sb = await Sandbox.create(
        "hello",
        image="python",
        memory=512,
        replace=True,
    )

    output = await sb.exec("python", ["-c", "print('Hello from a microVM!')"])
    print(output.stdout_text)  # Hello from a microVM!

    await sb.stop()

asyncio.run(main())