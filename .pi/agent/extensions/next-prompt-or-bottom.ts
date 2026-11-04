/**
 * Alt+Shift+O: jump to next prompt marker; if none, scroll to transcript end (follow).
 *
 * Built-in tui.altScreen.nextPrompt stops at the last OSC133 marker (top of last
 * user turn) and does nothing when there is no next marker. This mixes both.
 *
 * Requires keybindings.json to leave alt+shift+o unbound on nextPrompt so the
 * AltScreen viewport handler does not consume the key first.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type ScrollView = {
	scrollTop: number;
};

type ScrollTui = {
	scrollToBottom?: () => void;
	scrollToPrompt?: (direction: number) => void;
	getPrimaryScrollView?: () => ScrollView;
};

let tui: ScrollTui | undefined;

function captureTui(ctx: ExtensionContext): void {
	ctx.ui.setWidget("__next_prompt_or_bottom_tui", (ui: ScrollTui) => {
		tui = ui;
		return {
			render() {
				return [];
			},
			invalidate() {},
		};
	});
	ctx.ui.setWidget("__next_prompt_or_bottom_tui", undefined);
}

function nextPromptOrBottom(ctx: ExtensionContext): void {
	if (!tui?.scrollToPrompt || !tui.scrollToBottom) {
		captureTui(ctx);
	}
	if (!tui?.scrollToPrompt || !tui.scrollToBottom) {
		ctx.ui.notify("Fullscreen scroll unavailable", "warning");
		return;
	}

	const before = tui.getPrimaryScrollView?.()?.scrollTop;
	tui.scrollToPrompt(1);
	const after = tui.getPrimaryScrollView?.()?.scrollTop;

	if (before === undefined || before === after) {
		tui.scrollToBottom();
	}
}

export default function nextPromptOrBottomExtension(pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		captureTui(ctx);
	});

	pi.registerShortcut("alt+shift+o", {
		description: "Next prompt, or bottom if none",
		handler: async (ctx) => {
			nextPromptOrBottom(ctx);
		},
	});
}
