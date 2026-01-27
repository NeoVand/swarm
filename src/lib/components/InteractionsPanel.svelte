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
	import { getShapePath } from '$lib/utils/shapes';
	import { hslColor } from '$lib/utils/color';
	import CircleOff from '@lucide/svelte/icons/circle-off';
	import MoveUpLeft from '@lucide/svelte/icons/move-up-left';
	import Crosshair from '@lucide/svelte/icons/crosshair';
	import GitMerge from '@lucide/svelte/icons/git-merge';
	import ChevronsRight from '@lucide/svelte/icons/chevrons-right';
	import Orbit from '@lucide/svelte/icons/orbit';
	import Footprints from '@lucide/svelte/icons/footprints';
	import Shield from '@lucide/svelte/icons/shield';
	import Maximize2 from '@lucide/svelte/icons/maximize-2';
	import Swords from '@lucide/svelte/icons/swords';

	let currentParams = $derived($params);
	let activeSpecies = $derived(getActiveSpecies(currentParams));
	let allSpecies = $derived(currentParams.species);
	let otherSpecies = $derived(allSpecies.filter((s) => s.id !== activeSpecies?.id));

	// Dropdown state for target selection only
	let openTargetDropdown = $state<number | null>(null);

	// Behavior options with Lucide icons - 10 behaviors in 2 rows of 5
	const behaviorOptions = [
		// Row 1
		{ value: InteractionBehavior.Ignore, label: 'Ignore', Icon: CircleOff },
		{ value: InteractionBehavior.Flee, label: 'Flee', Icon: MoveUpLeft },
		{ value: InteractionBehavior.Chase, label: 'Chase', Icon: Crosshair },
		{ value: InteractionBehavior.Cohere, label: 'Cohere', Icon: GitMerge },
		{ value: InteractionBehavior.Align, label: 'Align', Icon: ChevronsRight },
		// Row 2
		{ value: InteractionBehavior.Orbit, label: 'Orbit', Icon: Orbit },
		{ value: InteractionBehavior.Follow, label: 'Follow', Icon: Footprints },
		{ value: InteractionBehavior.Guard, label: 'Guard', Icon: Shield },
		{ value: InteractionBehavior.Disperse, label: 'Scatter', Icon: Maximize2 },
		{ value: InteractionBehavior.Mob, label: 'Mob', Icon: Swords }
	];

	// Get species by ID
	function getSpeciesById(id: number): Species | undefined {
		return allSpecies.find((s) => s.id === id);
	}

	// Wrapper to get shape path with container size
	function getIconPath(shape: HeadShape, containerSize: number): string {
		const s = containerSize * 0.35;
		const cx = containerSize / 2;
		const cy = containerSize / 2;
		return getShapePath(shape, cx, cy, s);
	}

	// Handle behavior change
	function handleBehaviorChange(ruleIndex: number, behavior: InteractionBehavior) {
		if (!activeSpecies) return;
		updateInteractionRule(activeSpecies.id, ruleIndex, { behavior });
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

	// Toggle target dropdown
	function toggleTargetDropdown(ruleIndex: number) {
		openTargetDropdown = openTargetDropdown === ruleIndex ? null : ruleIndex;
	}

	// Close dropdown on click outside
	function handleClickOutside(event: MouseEvent) {
		const target = event.target as HTMLElement;
		if (!target.closest('.dropdown-wrapper')) {
			openTargetDropdown = null;
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
			behavior: InteractionBehavior.Flee,
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
					<!-- Header row: Source → Target + Delete -->
					<div class="rule-header">
						<div class="rule-flow">
							<!-- Source species icon -->
							<svg class="species-icon" viewBox="0 0 20 20">
								<path
									d={getIconPath(activeSpecies.headShape, 20)}
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
							<!-- Target dropdown -->
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
										<span class="target-label">Others</span>
									{:else}
										{@const target = getSpeciesById(rule.targetSpecies)}
										{#if target}
											<svg class="species-icon-sm" viewBox="0 0 20 20">
												<path
													d={getIconPath(target.headShape, 20)}
													fill={hslColor(target.hue, target.saturation, target.lightness)}
												/>
											</svg>
											<span class="target-label">{target.name}</span>
										{/if}
									{/if}
								</button>
								{#if openTargetDropdown === ruleIndex}
									<div
										class="dropdown-menu target-list"
										transition:slide={{ duration: 120, easing: cubicOut }}
									>
										<button
											class="target-item"
											class:active={rule.targetSpecies === -1}
											onclick={() => handleTargetChange(ruleIndex, -1)}
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
											<span class="target-item-label">All Others</span>
										</button>
										{#each otherSpecies as other (other.id)}
											<button
												class="target-item"
												class:active={rule.targetSpecies === other.id}
												onclick={() => handleTargetChange(ruleIndex, other.id)}
											>
												<svg class="species-icon-sm" viewBox="0 0 20 20">
													<path
														d={getIconPath(other.headShape, 20)}
														fill={hslColor(other.hue, other.saturation, other.lightness)}
													/>
												</svg>
												<span class="target-item-label">{other.name}</span>
											</button>
										{/each}
									</div>
								{/if}
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

					<!-- Behavior button grid (2 rows x 5 columns) -->
					<div class="behavior-grid">
						{#each behaviorOptions as opt (opt.value)}
							<button
								class="behavior-btn"
								class:active={rule.behavior === opt.value}
								onclick={() => handleBehaviorChange(ruleIndex, opt.value)}
								title={opt.label}
							>
								<opt.Icon size={16} strokeWidth={2} />
								<span class="behavior-label">{opt.label}</span>
							</button>
						{/each}
					</div>

					<!-- Strength and Range sliders -->
					{#if rule.behavior !== InteractionBehavior.Ignore}
						<div class="sliders-section">
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
		gap: 8px;
	}

	.rule-card {
		background: rgba(255, 255, 255, 0.02);
		border: 1px solid rgba(255, 255, 255, 0.06);
		border-radius: 8px;
		padding: 8px;
		display: flex;
		flex-direction: column;
		gap: 8px;
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
		padding: 3px 6px;
	}

	.target-label {
		font-size: 10px;
		color: rgba(255, 255, 255, 0.7);
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

	.dropdown-menu.target-list {
		min-width: 120px;
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding: 4px;
	}

	.target-item {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 8px;
		background: rgba(255, 255, 255, 0.02);
		border: none;
		border-radius: 4px;
		cursor: pointer;
		transition: background 0.1s;
	}

	.target-item:hover {
		background: rgba(255, 255, 255, 0.1);
	}

	.target-item.active {
		background: rgba(99, 102, 241, 0.25);
	}

	.target-item .all-icon {
		width: 16px;
		height: 16px;
		flex-shrink: 0;
	}

	.target-item .species-icon-sm {
		width: 16px;
		height: 16px;
		flex-shrink: 0;
	}

	.target-item-label {
		font-size: 11px;
		color: rgba(255, 255, 255, 0.8);
		white-space: nowrap;
	}

	.target-item:hover .target-item-label {
		color: rgba(255, 255, 255, 1);
	}

	.target-item.active .target-item-label {
		color: rgba(165, 180, 252, 1);
	}

	/* Behavior button grid - 2 rows x 5 columns */
	.behavior-grid {
		display: grid;
		grid-template-columns: repeat(5, 1fr);
		gap: 4px;
	}

	.behavior-btn {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 2px;
		padding: 6px 2px;
		background: rgba(255, 255, 255, 0.03);
		border: 1px solid transparent;
		border-radius: 6px;
		cursor: pointer;
		transition: all 0.15s;
		color: rgba(255, 255, 255, 0.5);
	}

	.behavior-btn:hover {
		background: rgba(255, 255, 255, 0.08);
		color: rgba(255, 255, 255, 0.8);
	}

	.behavior-btn.active {
		background: rgba(99, 102, 241, 0.2);
		border-color: rgba(99, 102, 241, 0.5);
		color: rgba(129, 140, 248, 1);
	}

	.behavior-btn .behavior-label {
		font-size: 7px;
		text-transform: uppercase;
		letter-spacing: 0.2px;
		white-space: nowrap;
		opacity: 0.7;
	}

	.behavior-btn:hover .behavior-label {
		opacity: 1;
	}

	.behavior-btn.active .behavior-label {
		color: rgba(165, 180, 252, 0.9);
		opacity: 1;
	}

	.sliders-section {
		padding-top: 4px;
		border-top: 1px solid rgba(255, 255, 255, 0.05);
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
