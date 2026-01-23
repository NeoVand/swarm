<script lang="ts">
	import { slide } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import {
		params,
		getActiveSpecies,
		updateInteractionRule,
		addInteractionRule,
		removeInteractionRule,
		type Species
	} from '$lib/stores/simulation';
	import { InteractionBehavior, HeadShape } from '$lib/webgpu/types';

	let currentParams = $derived($params);
	let activeSpecies = $derived(getActiveSpecies(currentParams));
	let allSpecies = $derived(currentParams.species);
	let otherSpecies = $derived(allSpecies.filter((s) => s.id !== activeSpecies?.id));

	// Dropdown states
	let openTargetDropdown = $state<number | null>(null);
	let openBehaviorDropdown = $state<number | null>(null);

	// Behavior options
	const behaviorOptions = [
		{ value: InteractionBehavior.Ignore, label: 'Ignore', icon: '○' },
		{ value: InteractionBehavior.Avoid, label: 'Avoid', icon: '←' },
		{ value: InteractionBehavior.Pursue, label: 'Pursue', icon: '→' },
		{ value: InteractionBehavior.Attract, label: 'Attract', icon: '◎' },
		{ value: InteractionBehavior.Mirror, label: 'Mirror', icon: '⇄' },
		{ value: InteractionBehavior.Orbit, label: 'Orbit', icon: '↻' }
	];

	// Get species by ID
	function getSpeciesById(id: number): Species | undefined {
		return allSpecies.find((s) => s.id === id);
	}

	// Convert HSL to color string
	function hslColor(hue: number, saturation: number, lightness: number): string {
		return `hsl(${hue}, ${saturation}%, ${lightness}%)`;
	}

	// Get behavior option by value
	function getBehaviorOption(value: InteractionBehavior) {
		return behaviorOptions.find((b) => b.value === value) || behaviorOptions[0];
	}

	// Get SVG path for species shape
	function getShapePath(shape: HeadShape, size: number): string {
		const s = size * 0.35;
		const cx = size / 2;
		const cy = size / 2;

		function polygon(sides: number): string {
			const points: string[] = [];
			for (let i = 0; i < sides; i++) {
				const angle = (2 * Math.PI * i) / sides;
				points.push(`${cx + Math.cos(angle) * s},${cy + Math.sin(angle) * s}`);
			}
			return `M ${points.join(' L ')} Z`;
		}

		switch (shape) {
			case HeadShape.Triangle:
				return `M ${cx + s} ${cy} L ${cx - s * 0.7} ${cy + s * 0.5} L ${cx - s * 0.7} ${cy - s * 0.5} Z`;
			case HeadShape.Square:
				return `M ${cx + s} ${cy} L ${cx} ${cy + s} L ${cx - s} ${cy} L ${cx} ${cy - s} Z`;
			case HeadShape.Pentagon:
				return polygon(5);
			case HeadShape.Hexagon:
				return polygon(6);
			case HeadShape.Arrow:
				return `M ${cx + s} ${cy} L ${cx - s * 0.5} ${cy + s * 0.6} L ${cx - s * 0.2} ${cy} L ${cx - s * 0.5} ${cy - s * 0.6} Z`;
			default:
				return `M ${cx + s} ${cy} L ${cx - s * 0.7} ${cy + s * 0.5} L ${cx - s * 0.7} ${cy - s * 0.5} Z`;
		}
	}

	// Handle behavior change
	function handleBehaviorChange(ruleIndex: number, behavior: InteractionBehavior) {
		if (!activeSpecies) return;
		updateInteractionRule(activeSpecies.id, ruleIndex, { behavior });
		openBehaviorDropdown = null;
	}

	// Handle strength change
	function handleStrengthChange(ruleIndex: number, strength: number) {
		if (!activeSpecies) return;
		updateInteractionRule(activeSpecies.id, ruleIndex, { strength });
	}

	// Handle range change
	function handleRangeChange(ruleIndex: number, range: number) {
		if (!activeSpecies) return;
		updateInteractionRule(activeSpecies.id, ruleIndex, { range });
	}

	// Handle target change
	function handleTargetChange(ruleIndex: number, targetSpecies: number | -1) {
		if (!activeSpecies) return;
		updateInteractionRule(activeSpecies.id, ruleIndex, { targetSpecies });
		openTargetDropdown = null;
	}

	// Toggle dropdowns
	function toggleTargetDropdown(ruleIndex: number) {
		openBehaviorDropdown = null;
		openTargetDropdown = openTargetDropdown === ruleIndex ? null : ruleIndex;
	}

	function toggleBehaviorDropdown(ruleIndex: number) {
		openTargetDropdown = null;
		openBehaviorDropdown = openBehaviorDropdown === ruleIndex ? null : ruleIndex;
	}

	// Close dropdowns on click outside
	function handleClickOutside(event: MouseEvent) {
		const target = event.target as HTMLElement;
		if (!target.closest('.dropdown-wrapper')) {
			openTargetDropdown = null;
			openBehaviorDropdown = null;
		}
	}

	// Add a new rule
	function handleAddRule() {
		if (!activeSpecies) return;
		const existingTargets = new Set(
			activeSpecies.interactions.filter((r) => r.targetSpecies !== -1).map((r) => r.targetSpecies)
		);
		const availableTarget = otherSpecies.find((s) => !existingTargets.has(s.id));
		const targetSpecies = availableTarget?.id ?? -1;

		addInteractionRule(activeSpecies.id, {
			targetSpecies,
			behavior: InteractionBehavior.Avoid,
			strength: 0.5,
			range: 0
		});
	}

	// Remove a rule
	function handleRemoveRule(ruleIndex: number) {
		if (!activeSpecies) return;
		removeInteractionRule(activeSpecies.id, ruleIndex);
	}
</script>

<svelte:window onclick={handleClickOutside} />

<div class="interactions-panel">
	{#if !activeSpecies}
		<div class="empty-state">No species selected</div>
	{:else if otherSpecies.length === 0}
		<div class="empty-state">
			<span class="empty-icon">+</span>
			<span>Add more species to configure interactions</span>
		</div>
	{:else}
		<div class="rules-list">
			{#each activeSpecies.interactions as rule, ruleIndex (ruleIndex)}
				<div class="rule-card" transition:slide={{ duration: 150, easing: cubicOut }}>
					<!-- Combined row: Source → Target + Behavior + Delete -->
					<div class="rule-header">
						<div class="rule-flow">
							<!-- Source species icon -->
							<svg class="species-icon" viewBox="0 0 20 20">
								<path
									d={getShapePath(activeSpecies.headShape, 20)}
									fill={hslColor(
										activeSpecies.hue,
										activeSpecies.saturation,
										activeSpecies.lightness
									)}
								/>
							</svg>
							<svg class="arrow-icon" viewBox="0 0 16 16" fill="currentColor">
								<path
									d="M4 8a.5.5 0 0 1 .5-.5h5.793L8.146 5.354a.5.5 0 1 1 .708-.708l3 3a.5.5 0 0 1 0 .708l-3 3a.5.5 0 0 1-.708-.708L10.293 8.5H4.5A.5.5 0 0 1 4 8z"
								/>
							</svg>
							<!-- Target dropdown (compact, no chevron) -->
							<div class="dropdown-wrapper">
								<button
									class="dropdown-btn compact"
									onclick={() => toggleTargetDropdown(ruleIndex)}
									title={rule.targetSpecies === -1
										? 'Others'
										: getSpeciesById(rule.targetSpecies)?.name}
								>
									{#if rule.targetSpecies === -1}
										<svg
											class="all-icon"
											viewBox="0 0 24 24"
											fill="none"
											stroke="rgba(255,255,255,0.8)"
											stroke-width="2"
											stroke-linecap="round"
											stroke-linejoin="round"
										>
											<path
												d="M8.3 10a.7.7 0 0 1-.626-1.079L11.4 3a.7.7 0 0 1 1.198-.043L16.3 8.9a.7.7 0 0 1-.572 1.1Z"
											/>
											<rect x="3" y="14" width="7" height="7" rx="1" />
											<circle cx="17.5" cy="17.5" r="3.5" />
										</svg>
									{:else}
										{@const target = getSpeciesById(rule.targetSpecies)}
										{#if target}
											<svg class="species-icon-sm" viewBox="0 0 20 20">
												<path
													d={getShapePath(target.headShape, 20)}
													fill={hslColor(target.hue, target.saturation, target.lightness)}
												/>
											</svg>
										{/if}
									{/if}
								</button>
								{#if openTargetDropdown === ruleIndex}
									<div
										class="dropdown-menu target-grid"
										transition:slide={{ duration: 120, easing: cubicOut }}
									>
										<button
											class="target-cell"
											class:active={rule.targetSpecies === -1}
											onclick={() => handleTargetChange(ruleIndex, -1)}
											title="All Others"
										>
											<svg
												class="all-icon"
												viewBox="0 0 24 24"
												fill="none"
												stroke="rgba(255,255,255,0.8)"
												stroke-width="2"
												stroke-linecap="round"
												stroke-linejoin="round"
											>
												<path
													d="M8.3 10a.7.7 0 0 1-.626-1.079L11.4 3a.7.7 0 0 1 1.198-.043L16.3 8.9a.7.7 0 0 1-.572 1.1Z"
												/>
												<rect x="3" y="14" width="7" height="7" rx="1" />
												<circle cx="17.5" cy="17.5" r="3.5" />
											</svg>
										</button>
										{#each otherSpecies as other (other.id)}
											<button
												class="target-cell"
												class:active={rule.targetSpecies === other.id}
												onclick={() => handleTargetChange(ruleIndex, other.id)}
												title={other.name}
											>
												<svg class="species-icon-sm" viewBox="0 0 20 20">
													<path
														d={getShapePath(other.headShape, 20)}
														fill={hslColor(other.hue, other.saturation, other.lightness)}
													/>
												</svg>
											</button>
										{/each}
									</div>
								{/if}
							</div>
							<!-- Behavior dropdown (compact, no chevron) - pushed to right -->
							<div class="behavior-group">
								<span class="inline-label">Behavior</span>
								<div class="dropdown-wrapper">
									<button
										class="dropdown-btn behavior-btn"
										onclick={() => toggleBehaviorDropdown(ruleIndex)}
										title={getBehaviorOption(rule.behavior).label}
									>
										<span class="behavior-icon">{getBehaviorOption(rule.behavior).icon}</span>
										<span class="behavior-label">{getBehaviorOption(rule.behavior).label}</span>
									</button>
									{#if openBehaviorDropdown === ruleIndex}
										<div
											class="dropdown-menu behavior-menu"
											transition:slide={{ duration: 120, easing: cubicOut }}
										>
											{#each behaviorOptions as opt (opt.value)}
												<button
													class="behavior-cell"
													class:active={rule.behavior === opt.value}
													onclick={() => handleBehaviorChange(ruleIndex, opt.value)}
												>
													<span class="behavior-cell-icon">{opt.icon}</span>
													<span class="behavior-cell-label">{opt.label}</span>
												</button>
											{/each}
										</div>
									{/if}
								</div>
							</div>
						</div>
						{#if activeSpecies.interactions.length > 1}
							<button class="remove-btn" onclick={() => handleRemoveRule(ruleIndex)} title="Remove">
								<svg viewBox="0 0 16 16" fill="currentColor">
									<path
										d="M5.5 5.5A.5.5 0 0 1 6 6v6a.5.5 0 0 1-1 0V6a.5.5 0 0 1 .5-.5zm2.5 0a.5.5 0 0 1 .5.5v6a.5.5 0 0 1-1 0V6a.5.5 0 0 1 .5-.5zm3 .5a.5.5 0 0 0-1 0v6a.5.5 0 0 0 1 0V6z"
									/>
									<path
										fill-rule="evenodd"
										d="M14.5 3a1 1 0 0 1-1 1H13v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V4h-.5a1 1 0 0 1-1-1V2a1 1 0 0 1 1-1H6a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1h3.5a1 1 0 0 1 1 1v1zM4.118 4 4 4.059V13a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1V4.059L11.882 4H4.118zM2.5 3V2h11v1h-11z"
									/>
								</svg>
							</button>
						{/if}
					</div>

					<!-- Strength and Range sliders -->
					{#if rule.behavior !== InteractionBehavior.Ignore}
						<div class="row">
							<span class="label">Strength</span>
							<input
								type="range"
								class="slider"
								min="0"
								max="1"
								step="0.05"
								value={rule.strength}
								oninput={(e) => handleStrengthChange(ruleIndex, parseFloat(e.currentTarget.value))}
							/>
							<span class="value">{(rule.strength * 100).toFixed(0)}%</span>
						</div>

						<div class="row">
							<span class="label">Range</span>
							<input
								type="range"
								class="slider"
								min="0"
								max="200"
								step="10"
								value={rule.range}
								oninput={(e) => handleRangeChange(ruleIndex, parseFloat(e.currentTarget.value))}
							/>
							<span class="value">{rule.range === 0 ? 'Auto' : rule.range}</span>
						</div>
					{/if}
				</div>
			{/each}
		</div>

		<button class="add-rule-btn" onclick={handleAddRule}>
			<svg viewBox="0 0 16 16" fill="currentColor">
				<path
					d="M8 4a.5.5 0 0 1 .5.5v3h3a.5.5 0 0 1 0 1h-3v3a.5.5 0 0 1-1 0v-3h-3a.5.5 0 0 1 0-1h3v-3A.5.5 0 0 1 8 4z"
				/>
			</svg>
			<span>Add Rule</span>
		</button>
	{/if}
</div>

<style>
	.interactions-panel {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.row {
		display: flex;
		align-items: center;
		gap: 4px;
		padding: 4px 0;
	}

	.label {
		width: 52px;
		flex-shrink: 0;
		font-size: 10px;
		color: rgb(161 161 170);
	}

	.value {
		width: 36px;
		flex-shrink: 0;
		text-align: right;
		font-family: ui-monospace, monospace;
		font-size: 9px;
		color: rgb(113 113 122);
	}

	.slider {
		flex: 1;
		min-width: 0;
		height: 4px;
		cursor: pointer;
		appearance: none;
		border-radius: 2px;
		background: linear-gradient(to right, rgba(161, 161, 170, 0.25), rgba(113, 113, 122, 0.15));
	}

	.slider::-webkit-slider-thumb {
		width: 14px;
		height: 14px;
		cursor: pointer;
		appearance: none;
		border-radius: 50%;
		background: rgb(8 8 12);
		border: 1px solid rgba(212, 212, 216, 0.8);
		box-shadow: 0 1px 4px rgba(0, 0, 0, 0.4);
		transition:
			transform 0.1s,
			border-color 0.1s;
	}

	.slider::-webkit-slider-thumb:hover {
		transform: scale(1.1);
		border-color: rgba(255, 255, 255, 0.9);
	}

	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 6px;
		padding: 16px 8px;
		color: rgba(255, 255, 255, 0.4);
		font-size: 11px;
		text-align: center;
	}

	.empty-icon {
		font-size: 20px;
		opacity: 0.5;
	}

	.rules-list {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.rule-card {
		background: rgba(255, 255, 255, 0.02);
		border: 1px solid rgba(255, 255, 255, 0.06);
		border-radius: 8px;
		padding: 6px 8px;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.rule-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}

	.rule-flow {
		display: flex;
		align-items: center;
		gap: 5px;
		flex: 1;
		min-width: 0;
	}

	.species-icon {
		width: 18px;
		height: 18px;
	}

	.species-icon-sm {
		width: 14px;
		height: 14px;
	}

	.all-icon {
		width: 16px;
		height: 16px;
	}

	.arrow-icon {
		width: 14px;
		height: 14px;
		color: rgba(255, 255, 255, 0.3);
	}

	.dropdown-wrapper {
		position: relative;
	}

	.dropdown-btn {
		display: flex;
		align-items: center;
		gap: 4px;
		padding: 4px 6px;
		background: rgba(255, 255, 255, 0.05);
		border: 1px solid rgba(255, 255, 255, 0.1);
		border-radius: 4px;
		cursor: pointer;
		transition: all 0.15s;
	}

	.dropdown-btn:hover {
		background: rgba(255, 255, 255, 0.08);
		border-color: rgba(255, 255, 255, 0.15);
	}

	.dropdown-btn.compact {
		padding: 3px 5px;
	}

	.dropdown-btn.behavior-btn {
		padding: 4px 8px;
		gap: 5px;
	}

	.behavior-group {
		display: flex;
		align-items: center;
		gap: 5px;
		margin-left: auto;
	}

	.inline-label {
		font-size: 9px;
		color: rgba(255, 255, 255, 0.5);
		text-transform: uppercase;
		letter-spacing: 0.3px;
		flex-shrink: 0;
	}

	.behavior-icon {
		font-size: 11px;
		color: rgba(255, 255, 255, 0.7);
		width: 14px;
		text-align: center;
		flex-shrink: 0;
	}

	.behavior-label {
		font-size: 10px;
		color: rgba(255, 255, 255, 0.8);
		white-space: nowrap;
	}

	.dropdown-menu {
		position: absolute;
		top: 100%;
		left: 0;
		min-width: 100%;
		margin-top: 4px;
		background: rgba(20, 20, 25, 0.98);
		border: 1px solid rgba(255, 255, 255, 0.12);
		border-radius: 6px;
		overflow: hidden;
		z-index: 50;
		box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
	}

	.dropdown-menu.behavior-menu {
		left: auto;
		right: 0;
		min-width: auto;
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 2px;
		padding: 4px;
	}

	.dropdown-menu.target-grid {
		min-width: auto;
		display: flex;
		flex-wrap: wrap;
		gap: 3px;
		padding: 5px;
		max-width: 140px;
	}

	.target-cell {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 26px;
		height: 26px;
		padding: 0;
		background: rgba(255, 255, 255, 0.04);
		border: none;
		border-radius: 4px;
		cursor: pointer;
		transition: background 0.1s;
	}

	.target-cell:hover {
		background: rgba(255, 255, 255, 0.12);
	}

	.target-cell.active {
		background: rgba(99, 102, 241, 0.3);
	}

	.target-cell .all-icon {
		width: 16px;
		height: 16px;
	}

	.target-cell .species-icon-sm {
		width: 16px;
		height: 16px;
	}

	.behavior-cell {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 2px;
		padding: 8px 12px;
		background: rgba(255, 255, 255, 0.03);
		border: none;
		border-radius: 4px;
		cursor: pointer;
		transition: background 0.1s;
	}

	.behavior-cell:hover {
		background: rgba(255, 255, 255, 0.1);
	}

	.behavior-cell.active {
		background: rgba(99, 102, 241, 0.25);
	}

	.behavior-cell-icon {
		font-size: 14px;
		color: rgba(255, 255, 255, 0.8);
	}

	.behavior-cell-label {
		font-size: 9px;
		color: rgba(255, 255, 255, 0.6);
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.remove-btn {
		width: 20px;
		height: 20px;
		padding: 0;
		margin-left: 8px;
		display: flex;
		align-items: center;
		justify-content: center;
		background: none;
		border: none;
		cursor: pointer;
		opacity: 0.4;
		transition: opacity 0.15s;
		flex-shrink: 0;
	}

	.remove-btn:hover {
		opacity: 0.8;
	}

	.remove-btn svg {
		width: 14px;
		height: 14px;
		color: rgba(239, 68, 68, 0.8);
	}

	.add-rule-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		padding: 8px;
		margin-top: 4px;
		background: rgba(255, 255, 255, 0.02);
		border: 1px dashed rgba(255, 255, 255, 0.12);
		border-radius: 6px;
		cursor: pointer;
		transition: all 0.15s;
	}

	.add-rule-btn:hover {
		background: rgba(99, 102, 241, 0.1);
		border-color: rgba(99, 102, 241, 0.3);
	}

	.add-rule-btn svg {
		width: 14px;
		height: 14px;
		color: rgba(255, 255, 255, 0.4);
	}

	.add-rule-btn span {
		font-size: 10px;
		color: rgba(255, 255, 255, 0.4);
		text-transform: uppercase;
		letter-spacing: 0.5px;
	}

	.add-rule-btn:hover svg,
	.add-rule-btn:hover span {
		color: rgba(99, 102, 241, 0.9);
	}
</style>
