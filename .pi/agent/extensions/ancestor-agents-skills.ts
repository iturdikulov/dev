/**
 * Подхватывает `.agents/skills` выше ближайшего git-root.
 *
 * Штатный поиск Pi идёт от cwd вверх только до ближайшего `.git`
 * (из workspace/foo до workspace/.agents/skills не доходит).
 * Этот экстеншен продолжает обход предков после git-root до $HOME
 * и отдаёт найденные `.agents/skills` через resources_discover.
 * `~/.agents/skills` не трогаем — Pi грузит их как user skills.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve, sep } from "node:path";

function ancestorAgentsSkills(cwd: string): string[] {
	const home = resolve(homedir());
	const skillPaths: string[] = [];
	let dir = resolve(cwd);
	let pastGitRoot = false;

	while (true) {
		if (dir === home) break;

		if (!pastGitRoot && existsSync(join(dir, ".git"))) {
			pastGitRoot = true;
		} else if (pastGitRoot) {
			const skills = join(dir, ".agents", "skills");
			if (existsSync(skills)) skillPaths.push(skills);
		}

		const parent = dirname(dir);
		if (parent === dir) break;
		if (parent !== home && !parent.startsWith(home + sep)) break;
		dir = parent;
	}

	return skillPaths;
}

export default function (pi: ExtensionAPI) {
	pi.on("resources_discover", ({ cwd }) => {
		const skillPaths = ancestorAgentsSkills(cwd);
		if (skillPaths.length === 0) return;
		return { skillPaths };
	});
}
