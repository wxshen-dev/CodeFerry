from __future__ import annotations

from codeferry.commands.registry import Command, CommandContext, CommandType


async def handle_do(ctx: CommandContext) -> None:
    ctx.ui.set_plan_mode(False)
    ctx.ui.add_system_message(
        "Switched to Execution mode - writes and command execution are enabled"
    )
    if ctx.args:
        ctx.ui.send_user_message(ctx.args)


DO_COMMAND = Command(
    name="do",
    aliases=["d"],
    description="Switch to Execution mode",
    usage="/do [task description]",
    type=CommandType.LOCAL_UI,
    handler=handle_do,
)
