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
	import CircleSlash from '@lucide/svelte/icons/circle-slash';
	import MoveUpLeft from '@lucide/svelte/icons/move-up-left';
	import Target from '@lucide/svelte/icons/target';
	import GitMerge from '@lucide/svelte/icons/git-merge';
	import ChevronsRight from '@lucide/svelte/icons/chevrons-right';
	import Globe from '@lucide/svelte/icons/globe';
	import Footprints from '@lucide/svelte/icons/footprints';
	import Shield from '@lucide/svelte/icons/shield';
	import Maximize2 from '@lucide/svelte/icons/maximize-2';
	import Swords from '@lucide/svelte/icons/swords';
	import Settings from '@lucide/svelte/icons/settings';
	import ChevronDown from '@lucide/svelte/icons/chevron-down';
	import Trash2 from '@lucide/svelte/icons/trash-2';

	let currentParams = $derived($params);
	let activeSpecies = $derived(getActiveSpecies(currentParams));
	let allSpecies = $derived(currentParams.species);
	let otherSpecies = $derived(allSpecies.filter((s) => s.id !== activeSpecies?.id));

	// Compute which targets are already assigned (for filtering dropdowns)
	let assignedTargets = $derived(
		new Set(
			activeSpecies?.interactions
				.filter((r) => r.targetSpecies !== -1)
				.map((r) => r.targetSpecies) ?? []
		)
	);

	// Check if there's already an "All" rule
	let hasAllRule = $derived(
		activeSpecies?.interactions.some((r) => r.targetSpecies === -1) ?? false
	);

	// Available targets for a new rule (excludes already assigned, and "All" if it exists)
	let canAddMoreRules = $derived(() => {
		if (!activeSpecies) return false;
		// Can add if there are unassigned specific targets
		const unassignedCount = otherSpecies.filter((s) => !assignedTargets.has(s.id)).length;
		// Can add if we don't have an "All" rule yet, or if there are unassigned specific targets
		return unassignedCount > 0 || !hasAllRule;
	});

	// Get available targets for a specific rule (excluding already assigned, except current)
	function getAvailableTargetsForRule(currentRuleIndex: number): Species[] {
		if (!activeSpecies) return [];
		const currentTarget = activeSpecies.interactions[currentRuleIndex]?.targetSpecies;
		return otherSpecies.filter((s) => {
			// Include if it's the current target or if it's not already assigned
			return s.id === currentTarget || !assignedTargets.has(s.id);
		});
	}

	// Check if "All" option should be available for a rule
	function canSelectAll(currentRuleIndex: number): boolean {
		if (!activeSpecies) return false;
		const currentTarget = activeSpecies.interactions[currentRuleIndex]?.targetSpecies;
		// Can select "All" if this rule is already "All", or if no other rule is "All"
		return currentTarget === -1 || !hasAllRule;
	}

	// Dropdown and expanded states
	let openTargetDropdown = $state<number | null>(null);
	let openBehaviorDropdown = $state<number | null>(null);
	let expandedSettings = $state<Set<number>>(new Set());

	// Behavior options with Lucide icons and colors (matching tour card)
	const behaviorOptions = [
		{ value: InteractionBehavior.Ignore, label: 'Ignore', Icon: CircleSlash, color: '#71717a' },
		{ value: InteractionBehavior.Flee, label: 'Flee', Icon: MoveUpLeft, color: '#f87171' },
		{ value: InteractionBehavior.Chase, label: 'Chase', Icon: Target, color: '#fb923c' },
		{ value: InteractionBehavior.Cohere, label: 'Cohere', Icon: GitMerge, color: '#22d3ee' },
		{ value: InteractionBehavior.Align, label: 'Align', Icon: ChevronsRight, color: '#a78bfa' },
		{ value: InteractionBehavior.Orbit, label: 'Orbit', Icon: Globe, color: '#f97316' },
		{ value: InteractionBehavior.Follow, label: 'Follow', Icon: Footprints, color: '#34d399' },
		{ value: InteractionBehavior.Guard, label: 'Guard', Icon: Shield, color: '#38bdf8' },
		{ value: InteractionBehavior.Disperse, label: 'Scatter', Icon: Maximize2, color: '#fbbf24' },
		{ value: InteractionBehavior.Mob, label: 'Mob', Icon: Swords, color: '#ef4444' }
	];

	// Get behavior option by value
	function getBehaviorOption(value: InteractionBehavior) {
		return behaviorOptions.find((b) => b.value === value) ?? behaviorOptions[0];
	}

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

	// Toggle settings expansion
	function toggleSettings(ruleIndex: number) {
		const newSet = new Set(expandedSettings);
		if (newSet.has(ruleIndex)) {
			newSet.delete(ruleIndex);
		} else {
			newSet.add(ruleIndex);
		}
		expandedSettings = newSet;
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
		
		// Find an available target (not already assigned)
		const availableTarget = otherSpecies.find((s) => !assignedTargets.has(s.id));
		
		// If all specific targets are assigned, add an "All" rule (if not already present)
		if (!availableTarget) {
			if (!hasAllRule) {
				addInteractionRule(activeSpecies.id, {
					targetSpecies: -1,
					behavior: InteractionBehavior.Flee,
					strength: 0.5,
					range: 0
				});
			}
			return;
		}

		addInteractionRule(activeSpecies.id, {
			targetSpecies: availableTarget.id,
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
				{@const behaviorOpt = getBehaviorOption(rule.behavior)}
				{@const isExpanded = expandedSettings.has(ruleIndex)}
				<div class="rule-row" transition:slide={{ duration: 150, easing: cubicOut }}>
					<!-- Main row: Source → Target → Behavior → Settings -->
					<div class="rule-main">
						<!-- Source species icon -->
						<svg class="species-icon" viewBox="0 0 20 20">
							<path
								d={getIconPath(activeSpecies.headShape, 20)}
								fill={hslColor(activeSpecies.hue, activeSpecies.saturation, activeSpecies.lightness)}
							/>
						</svg>

						<span class="arrow">→</span>

						<!-- Target dropdown (icons only) -->
						<div class="dropdown-wrapper">
							<button
								class="target-btn"
								onclick={() => toggleTargetDropdown(ruleIndex)}
								title={rule.targetSpecies === -1 ? 'All Others' : getSpeciesById(rule.targetSpecies)?.name}
							>
								{#if rule.targetSpecies === -1}
									<span class="all-text">All</span>
								{:else}
									{@const target = getSpeciesById(rule.targetSpecies)}
									{#if target}
										<svg class="species-icon-sm" viewBox="0 0 20 20">
											<path
												d={getIconPath(target.headShape, 20)}
												fill={hslColor(target.hue, target.saturation, target.lightness)}
											/>
										</svg>
									{/if}
								{/if}
								<ChevronDown size={10} strokeWidth={2} />
							</button>
							{#if openTargetDropdown === ruleIndex}
								{@const availableTargets = getAvailableTargetsForRule(ruleIndex)}
								{@const showAllOption = canSelectAll(ruleIndex)}
								<div class="dropdown-menu compact">
									{#if showAllOption}
										<button
											class="dropdown-item"
											class:active={rule.targetSpecies === -1}
											onclick={() => handleTargetChange(ruleIndex, -1)}
											title="All other species (fallback)"
										>
											<span class="all-text">All</span>
										</button>
									{/if}
									{#each availableTargets as other (other.id)}
										<button
											class="dropdown-item"
											class:active={rule.targetSpecies === other.id}
											onclick={() => handleTargetChange(ruleIndex, other.id)}
											title={other.name}
										>
											<svg class="species-icon-sm" viewBox="0 0 20 20">
												<path
													d={getIconPath(other.headShape, 20)}
													fill={hslColor(other.hue, other.saturation, other.lightness)}
												/>
											</svg>
										</button>
									{/each}
								</div>
							{/if}
						</div>

						<!-- Behavior dropdown -->
						<div class="dropdown-wrapper behavior-dropdown">
							<button
								class="behavior-btn"
								onclick={() => toggleBehaviorDropdown(ruleIndex)}
								style="--behavior-color: {behaviorOpt.color}"
							>
								<behaviorOpt.Icon size={14} strokeWidth={2} color={behaviorOpt.color} />
								<span class="behavior-label">{behaviorOpt.label}</span>
								<ChevronDown size={10} strokeWidth={2} />
							</button>
							{#if openBehaviorDropdown === ruleIndex}
								<div class="dropdown-menu behavior-grid-menu">
									{#each behaviorOptions as opt (opt.value)}
										<button
											class="behavior-grid-item"
											class:active={rule.behavior === opt.value}
											onclick={() => handleBehaviorChange(ruleIndex, opt.value)}
											title={opt.label}
											style="--behavior-color: {opt.color}"
										>
											<opt.Icon size={14} strokeWidth={2} color={opt.color} />
											<span>{opt.label}</span>
										</button>
									{/each}
								</div>
							{/if}
						</div>

						<!-- Settings toggle (only show if not Ignore) -->
						{#if rule.behavior !== InteractionBehavior.Ignore}
							<button
								class="settings-btn"
								class:active={isExpanded}
								onclick={() => toggleSettings(ruleIndex)}
								title="Settings"
							>
								<Settings size={14} strokeWidth={2} />
							</button>
						{/if}

						<!-- Delete button -->
						{#if activeSpecies.interactions.length > 1}
							<button
								class="delete-btn"
								onclick={() => handleRemoveRule(ruleIndex)}
								title="Remove rule"
							>
								<Trash2 size={12} strokeWidth={2} />
							</button>
						{/if}
					</div>

					<!-- Expanded settings (Strength/Range sliders) -->
					{#if isExpanded && rule.behavior !== InteractionBehavior.Ignore}
						<div class="settings-panel" transition:slide={{ duration: 120, easing: cubicOut }}>
							<div class="slider-row">
								<span class="slider-label">Str</span>
								<input
									type="range"
									class="slider"
									min="0"
									max="1"
									step="0.05"
									value={rule.strength}
									oninput={(e) => handleStrengthChange(ruleIndex, parseFloat(e.currentTarget.value))}
								/>
								<span class="slider-value">{(rule.strength * 100).toFixed(0)}%</span>
							</div>
							<div class="slider-row">
								<span class="slider-label">Rng</span>
								<input
									type="range"
									class="slider"
									min="0"
									max="200"
									step="10"
									value={rule.range}
									oninput={(e) => handleRangeChange(ruleIndex, parseFloat(e.currentTarget.value))}
								/>
								<span class="slider-value">{rule.range === 0 ? 'Auto' : rule.range}</span>
							</div>
						</div>
					{/if}
				</div>
			{/each}
		</div>

		{#if canAddMoreRules()}
			<button class="add-rule-btn" onclick={handleAddRule}>
				<svg viewBox="0 0 16 16" fill="currentColor">
					<path d="M8 4a.5.5 0 0 1 .5.5v3h3a.5.5 0 0 1 0 1h-3v3a.5.5 0 0 1-1 0v-3h-3a.5.5 0 0 1 0-1h3v-3A.5.5 0 0 1 8 4z" />
				</svg>
				<span>Add Rule</span>
			</button>
		{/if}
	{/if}
</div>

<style>
	.interactions-panel {
		display: flex;
		flex-direction: column;
		gap: 4px;
		overflow: visible;
		position: relative;
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
		gap: 4px;
		overflow: visible;
	}

	.rule-row {
		background: rgba(255, 255, 255, 0.02);
		border: 1px solid rgba(255, 255, 255, 0.06);
		border-radius: 6px;
		position: relative;
		overflow: visible;
	}

	.rule-main {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 6px 8px;
		position: relative;
		overflow: visible;
	}

	.species-icon {
		width: 18px;
		height: 18px;
		flex-shrink: 0;
	}

	.species-icon-sm {
		width: 14px;
		height: 14px;
	}

	.arrow {
		font-size: 10px;
		color: rgba(255, 255, 255, 0.3);
		flex-shrink: 0;
	}

	/* Target dropdown */
	.dropdown-wrapper {
		position: relative;
	}

	.target-btn {
		display: flex;
		align-items: center;
		gap: 3px;
		padding: 3px 5px;
		background: rgba(255, 255, 255, 0.05);
		border: 1px solid rgba(255, 255, 255, 0.1);
		border-radius: 4px;
		cursor: pointer;
		transition: all 0.15s;
		color: rgba(255, 255, 255, 0.6);
	}

	.target-btn:hover {
		background: rgba(255, 255, 255, 0.08);
		border-color: rgba(255, 255, 255, 0.15);
	}

	.all-text {
		font-size: 9px;
		font-weight: 500;
		color: rgba(255, 255, 255, 0.7);
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	/* Behavior dropdown */
	.behavior-dropdown {
		flex: 1;
		min-width: 0;
	}

	.behavior-btn {
		display: flex;
		align-items: center;
		gap: 4px;
		width: 100%;
		padding: 3px 6px;
		background: rgba(255, 255, 255, 0.05);
		border: 1px solid rgba(255, 255, 255, 0.1);
		border-radius: 4px;
		cursor: pointer;
		transition: all 0.15s;
		color: rgba(255, 255, 255, 0.7);
	}

	.behavior-btn:hover {
		background: rgba(255, 255, 255, 0.08);
		border-color: rgba(255, 255, 255, 0.15);
	}

	.behavior-label {
		flex: 1;
		font-size: 10px;
		text-align: left;
	}

	/* Dropdown menus */
	.dropdown-menu {
		position: absolute;
		top: 100%;
		left: 0;
		margin-top: 2px;
		background: rgba(20, 20, 25, 0.98);
		border: 1px solid rgba(255, 255, 255, 0.12);
		border-radius: 6px;
		z-index: 9999;
		box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
	}

	.dropdown-menu.compact {
		display: flex;
		flex-direction: row;
		gap: 2px;
		padding: 4px;
	}

	.dropdown-menu.behavior-grid-menu {
		display: grid;
		grid-template-columns: repeat(4, 36px);
		gap: 3px;
		padding: 6px;
		right: 0;
		left: auto;
	}

	.behavior-grid-item {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 2px;
		width: 36px;
		height: 36px;
		padding: 2px;
		background: rgba(255, 255, 255, 0.03);
		border: 1px solid transparent;
		border-radius: 4px;
		cursor: pointer;
		transition: all 0.12s;
		color: rgba(255, 255, 255, 0.5);
		overflow: hidden;
	}

	.behavior-grid-item:hover {
		background: rgba(255, 255, 255, 0.1);
		color: rgba(255, 255, 255, 0.85);
	}

	.behavior-grid-item.active {
		background: rgba(99, 102, 241, 0.25);
		border-color: rgba(99, 102, 241, 0.5);
		color: rgba(129, 140, 248, 1);
	}

	.behavior-grid-item span {
		font-size: 6px;
		text-transform: uppercase;
		letter-spacing: 0.1px;
		white-space: nowrap;
		opacity: 0.7;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 100%;
	}

	.behavior-grid-item:hover span {
		opacity: 1;
	}

	.behavior-grid-item.active span {
		color: rgba(165, 180, 252, 0.9);
		opacity: 1;
	}

	.dropdown-item {
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 4px 6px;
		background: none;
		border: none;
		border-radius: 3px;
		cursor: pointer;
		transition: background 0.1s;
		color: rgba(255, 255, 255, 0.7);
	}

	.dropdown-item:hover {
		background: rgba(255, 255, 255, 0.1);
	}

	.dropdown-item.active {
		background: rgba(99, 102, 241, 0.25);
		color: rgba(165, 180, 252, 1);
	}


	/* Settings and delete buttons */
	.settings-btn,
	.delete-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 22px;
		height: 22px;
		padding: 0;
		background: none;
		border: none;
		border-radius: 4px;
		cursor: pointer;
		color: rgba(255, 255, 255, 0.4);
		transition: all 0.15s;
		flex-shrink: 0;
	}

	.settings-btn:hover {
		background: rgba(255, 255, 255, 0.08);
		color: rgba(255, 255, 255, 0.7);
	}

	.settings-btn.active {
		background: rgba(99, 102, 241, 0.2);
		color: rgba(129, 140, 248, 1);
	}

	.delete-btn:hover {
		background: rgba(239, 68, 68, 0.15);
		color: rgba(239, 68, 68, 0.9);
	}

	/* Settings panel with sliders */
	.settings-panel {
		padding: 6px 8px 8px;
		border-top: 1px solid rgba(255, 255, 255, 0.05);
		background: rgba(0, 0, 0, 0.15);
	}

	.slider-row {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 2px 0;
	}

	.slider-label {
		width: 24px;
		flex-shrink: 0;
		font-size: 9px;
		color: rgba(255, 255, 255, 0.5);
		text-transform: uppercase;
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
		width: 12px;
		height: 12px;
		cursor: pointer;
		appearance: none;
		border-radius: 50%;
		background: rgb(8 8 12);
		border: 1px solid rgba(212, 212, 216, 0.8);
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.4);
		transition: transform 0.1s, border-color 0.1s;
	}

	.slider::-webkit-slider-thumb:hover {
		transform: scale(1.1);
		border-color: rgba(255, 255, 255, 0.9);
	}

	.slider-value {
		width: 32px;
		flex-shrink: 0;
		text-align: right;
		font-family: ui-monospace, monospace;
		font-size: 9px;
		color: rgba(255, 255, 255, 0.5);
	}

	/* Add rule button */
	.add-rule-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		padding: 6px;
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
		width: 12px;
		height: 12px;
		color: rgba(255, 255, 255, 0.4);
	}

	.add-rule-btn span {
		font-size: 9px;
		color: rgba(255, 255, 255, 0.4);
		text-transform: uppercase;
		letter-spacing: 0.5px;
	}

	.add-rule-btn:hover svg,
	.add-rule-btn:hover span {
		color: rgba(99, 102, 241, 0.9);
	}
</style>
