<script lang="ts">
	import { slide } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import {
		params,
		getActiveSpecies,
		updateInteractionRule,
		addInteractionRule,
		removeInteractionRule,
		type Species,
		type InteractionRuleType
	} from '$lib/stores/simulation';
	import { InteractionBehavior, HeadShape, MetricSource, MetricRole, MAX_METRIC_RULES_PER_SPECIES } from '$lib/webgpu/types';
	import { getShapePath } from '$lib/utils/shapes';
	import { hslColor } from '$lib/utils/color';
	import CurveEditor from './CurveEditor.svelte';
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
	import FlipHorizontal2 from '@lucide/svelte/icons/flip-horizontal-2';
	import LoaderCircle from '@lucide/svelte/icons/loader-circle';
	import Settings from '@lucide/svelte/icons/settings';
	import ChevronDown from '@lucide/svelte/icons/chevron-down';
	import Trash2 from '@lucide/svelte/icons/trash-2';
	import Plus from '@lucide/svelte/icons/plus';

	let currentParams = $derived($params);
	let activeSpecies = $derived(getActiveSpecies(currentParams));
	let allSpecies = $derived(currentParams.species);
	let otherSpecies = $derived(allSpecies.filter((s) => s.id !== activeSpecies?.id));

	// Separate species-based and metric-based rules
	let speciesRules = $derived(
		activeSpecies?.interactions.filter((r) => r.type !== 'metric') ?? []
	);
	let metricRules = $derived(
		activeSpecies?.interactions.filter((r) => r.type === 'metric') ?? []
	);

	// Compute which targets are already assigned (for filtering dropdowns) - only for species rules
	let assignedTargets = $derived(
		new Set(
			speciesRules
				.filter((r) => r.targetSpecies !== -1)
				.map((r) => r.targetSpecies)
		)
	);

	// Check if there's already an "All" rule (only for species rules)
	let hasAllRule = $derived(
		speciesRules.some((r) => r.targetSpecies === -1)
	);

	// Check if we can add more metric rules (max 2 per species)
	let canAddMoreMetricRules = $derived(metricRules.length < MAX_METRIC_RULES_PER_SPECIES);

	// Available targets for a new species rule
	let canAddMoreSpeciesRules = $derived(() => {
		if (!activeSpecies) return false;
		const unassignedCount = otherSpecies.filter((s) => !assignedTargets.has(s.id)).length;
		return unassignedCount > 0 || !hasAllRule;
	});

	// Can add any rule at all
	let canAddMoreRules = $derived(() => {
		return canAddMoreSpeciesRules() || canAddMoreMetricRules;
	});

	// Metric source options - matches the available computed metrics on GPU
	// These map to metricsOut: [density, anisotropy, turning, influence]
	const metricSourceOptions = [
		{ value: MetricSource.Speed, label: 'Speed' },
		{ value: MetricSource.Orientation, label: 'Direction' },
		{ value: MetricSource.Neighbors, label: 'Neighbors' },
		{ value: MetricSource.LocalDensity, label: 'Density' },
		{ value: MetricSource.Anisotropy, label: 'Structure' },
		{ value: MetricSource.TurnRate, label: 'Turn Rate' },
		{ value: MetricSource.Acceleration, label: 'Accel' },
		{ value: MetricSource.Spectral, label: 'Spectral' }
	];

	// Metric role options
	const metricRoleOptions = [
		{ value: MetricRole.Neighbor, label: 'Neighbor' },
		{ value: MetricRole.Self, label: 'Self' },
		{ value: MetricRole.Difference, label: 'Difference' }
	];

	// Get label for metric source
	function getMetricLabel(src: MetricSource): string {
		return metricSourceOptions.find(o => o.value === src)?.label ?? 'Unknown';
	}

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
	let openMetricSourceDropdown = $state<number | null>(null);
	let openMetricRoleDropdown = $state<number | null>(null);
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
		{ value: InteractionBehavior.Mob, label: 'Mob', Icon: Swords, color: '#ef4444' },
		{ value: InteractionBehavior.Mirror, label: 'Mirror', Icon: FlipHorizontal2, color: '#c084fc' },
		{ value: InteractionBehavior.Spiral, label: 'Spiral', Icon: LoaderCircle, color: '#2dd4bf' }
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

	// Handle metric source change
	function handleMetricSourceChange(ruleIndex: number, metricSource: MetricSource) {
		if (!activeSpecies) return;
		updateInteractionRule(activeSpecies.id, ruleIndex, { metricSource });
		openMetricSourceDropdown = null;
	}

	// Handle metric role change
	function handleMetricRoleChange(ruleIndex: number, metricRole: MetricRole) {
		if (!activeSpecies) return;
		updateInteractionRule(activeSpecies.id, ruleIndex, { metricRole });
		openMetricRoleDropdown = null;
	}

	// Handle curve change for metric rules
	function handleCurveChange(ruleIndex: number, points: Array<{x: number; y: number}>) {
		if (!activeSpecies) return;
		updateInteractionRule(activeSpecies.id, ruleIndex, { curve: points });
	}

	// Toggle dropdowns
	function toggleTargetDropdown(ruleIndex: number) {
		closeAllDropdowns();
		openTargetDropdown = openTargetDropdown === ruleIndex ? null : ruleIndex;
	}

	function toggleBehaviorDropdown(ruleIndex: number) {
		closeAllDropdowns();
		openBehaviorDropdown = openBehaviorDropdown === ruleIndex ? null : ruleIndex;
	}

	function toggleMetricSourceDropdown(ruleIndex: number) {
		closeAllDropdowns();
		openMetricSourceDropdown = openMetricSourceDropdown === ruleIndex ? null : ruleIndex;
	}

	function toggleMetricRoleDropdown(ruleIndex: number) {
		closeAllDropdowns();
		openMetricRoleDropdown = openMetricRoleDropdown === ruleIndex ? null : ruleIndex;
	}

	function closeAllDropdowns() {
		openTargetDropdown = null;
		openBehaviorDropdown = null;
		openMetricSourceDropdown = null;
		openMetricRoleDropdown = null;
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
			closeAllDropdowns();
		}
	}

	// Get metric source option by value
	function getMetricSourceOption(value: MetricSource) {
		return metricSourceOptions.find((o) => o.value === value) ?? metricSourceOptions[0];
	}

	// Get metric role option by value
	function getMetricRoleOption(value: MetricRole) {
		return metricRoleOptions.find((o) => o.value === value) ?? metricRoleOptions[0];
	}

	// Add a new species rule
	function handleAddSpeciesRule() {
		if (!activeSpecies) return;
		closeAllDropdowns();
		
		// Find an available target (not already assigned)
		const availableTarget = otherSpecies.find((s) => !assignedTargets.has(s.id));
		
		// If all specific targets are assigned, add an "All" rule (if not already present)
		if (!availableTarget) {
			if (!hasAllRule) {
				addInteractionRule(activeSpecies.id, {
					type: 'species',
					targetSpecies: -1,
					behavior: InteractionBehavior.Flee,
					strength: 0.5,
					range: 0
				});
			}
			return;
		}

		addInteractionRule(activeSpecies.id, {
			type: 'species',
			targetSpecies: availableTarget.id,
			behavior: InteractionBehavior.Flee,
			strength: 0.5,
			range: 0
		});
	}

	// Add a new metric rule
	function handleAddMetricRule() {
		if (!activeSpecies || !canAddMoreMetricRules) return;
		closeAllDropdowns();

		addInteractionRule(activeSpecies.id, {
			type: 'metric',
			metricSource: MetricSource.LocalDensity,
			metricRole: MetricRole.Neighbor,
			behavior: InteractionBehavior.Flee,
			strength: 0.5,
			range: 0,
			curve: [
				{ x: 0, y: 0 },
				{ x: 1, y: 1 }
			]
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
	{:else}
		<div class="rules-list">
			{#each activeSpecies.interactions as rule, ruleIndex (ruleIndex)}
				{@const behaviorOpt = getBehaviorOption(rule.behavior)}
				{@const isExpanded = expandedSettings.has(ruleIndex)}
				{@const isMetricRule = rule.type === 'metric'}
				<div class="rule-row" class:metric-rule={isMetricRule} transition:slide={{ duration: 150, easing: cubicOut }}>
					{#if isMetricRule}
						<!-- METRIC RULE: Single row layout matching species rules -->
						{@const metricSrc = rule.metricSource ?? MetricSource.LocalDensity}
						{@const metricRole = rule.metricRole ?? MetricRole.Neighbor}
						<div class="rule-main">
							<!-- Metric Source dropdown (icon only) -->
							<div class="dropdown-wrapper">
								<button
									class="target-btn"
									onclick={() => toggleMetricSourceDropdown(ruleIndex)}
									title={getMetricLabel(metricSrc)}
								>
									{#if metricSrc === MetricSource.Speed}
										<svg class="species-icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/></svg>
									{:else if metricSrc === MetricSource.Orientation}
										<svg class="species-icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76" fill="currentColor" stroke="none"/></svg>
									{:else if metricSrc === MetricSource.Neighbors}
										<svg class="species-icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
									{:else if metricSrc === MetricSource.LocalDensity}
										<svg class="species-icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 12.5-8.97 4.08a2 2 0 0 1-1.66 0L2 12.5"/><path d="m22 17.5-8.97 4.08a2 2 0 0 1-1.66 0L2 17.5"/></svg>
									{:else if metricSrc === MetricSource.Anisotropy}
										<svg class="species-icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/><line x1="7" x2="17" y1="12" y2="12"/></svg>
									{:else if metricSrc === MetricSource.TurnRate}
										<svg class="species-icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>
									{:else if metricSrc === MetricSource.Acceleration}
										<svg class="species-icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/></svg>
									{:else if metricSrc === MetricSource.Spectral}
										<svg class="species-icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 2v10l7 7"/></svg>
									{/if}
									<ChevronDown size={10} strokeWidth={2} />
								</button>
								{#if openMetricSourceDropdown === ruleIndex}
									<div class="dropdown-menu labeled-menu">
										{#each metricSourceOptions as opt (opt.value)}
											<button
												class="dropdown-item labeled-item"
												class:active={rule.metricSource === opt.value}
												onclick={() => handleMetricSourceChange(ruleIndex, opt.value)}
											>
												{#if opt.value === MetricSource.Speed}
													<svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/></svg>
												{:else if opt.value === MetricSource.Orientation}
													<svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76" fill="currentColor" stroke="none"/></svg>
												{:else if opt.value === MetricSource.Neighbors}
													<svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
												{:else if opt.value === MetricSource.LocalDensity}
													<svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 12.5-8.97 4.08a2 2 0 0 1-1.66 0L2 12.5"/><path d="m22 17.5-8.97 4.08a2 2 0 0 1-1.66 0L2 17.5"/></svg>
												{:else if opt.value === MetricSource.Anisotropy}
													<svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/><line x1="7" x2="17" y1="12" y2="12"/></svg>
												{:else if opt.value === MetricSource.TurnRate}
													<svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>
												{:else if opt.value === MetricSource.Acceleration}
													<svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/></svg>
												{:else if opt.value === MetricSource.Spectral}
													<svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 2v10l7 7"/></svg>
												{/if}
												<span>{opt.label}</span>
											</button>
										{/each}
									</div>
								{/if}
							</div>

							<span class="metric-of">of</span>

							<!-- Metric Role dropdown (icon only) -->
							<div class="dropdown-wrapper">
								<button
									class="target-btn"
									onclick={() => toggleMetricRoleDropdown(ruleIndex)}
									title={getMetricRoleOption(metricRole).label}
								>
									{#if metricRole === MetricRole.Neighbor}
										<!-- users icon -->
										<svg class="species-icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
									{:else if metricRole === MetricRole.Self}
										<!-- user icon -->
										<svg class="species-icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
									{:else if metricRole === MetricRole.Difference}
										<!-- delta icon -->
										<svg class="species-icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4L4 20h16L12 4z"/></svg>
									{/if}
									<ChevronDown size={10} strokeWidth={2} />
								</button>
								{#if openMetricRoleDropdown === ruleIndex}
									<div class="dropdown-menu labeled-menu">
										{#each metricRoleOptions as opt (opt.value)}
											<button
												class="dropdown-item labeled-item"
												class:active={rule.metricRole === opt.value}
												onclick={() => handleMetricRoleChange(ruleIndex, opt.value)}
											>
												{#if opt.value === MetricRole.Neighbor}
													<svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
												{:else if opt.value === MetricRole.Self}
													<svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
												{:else if opt.value === MetricRole.Difference}
													<svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4L4 20h16L12 4z"/></svg>
												{/if}
												<span>{opt.label}</span>
											</button>
										{/each}
									</div>
								{/if}
							</div>

							<!-- Behavior dropdown (icon only in button) -->
							<div class="dropdown-wrapper">
								<button
									class="target-btn"
									onclick={() => toggleBehaviorDropdown(ruleIndex)}
									title={behaviorOpt.label}
									style="color: {behaviorOpt.color}"
								>
									<behaviorOpt.Icon size={14} strokeWidth={2} color={behaviorOpt.color} />
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

							<!-- Right-aligned actions -->
							<div class="rule-actions">
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
								<button
									class="delete-btn"
									onclick={() => handleRemoveRule(ruleIndex)}
									title="Remove rule"
								>
									<Trash2 size={12} strokeWidth={2} />
								</button>
							</div>
						</div>
					{:else}
						<!-- SPECIES RULE: Single row layout (unchanged) -->
						<div class="rule-main">
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
									title={rule.targetSpecies === -1 ? 'All Others' : getSpeciesById(rule.targetSpecies ?? -1)?.name}
								>
									{#if rule.targetSpecies === -1}
										<span class="all-text">All</span>
									{:else}
										{@const target = getSpeciesById(rule.targetSpecies ?? -1)}
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

							<!-- Right-aligned actions -->
							<div class="rule-actions">
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
								<button
									class="delete-btn"
									onclick={() => handleRemoveRule(ruleIndex)}
									title="Remove rule"
								>
									<Trash2 size={12} strokeWidth={2} />
								</button>
							</div>
						</div>
					{/if}

					<!-- Expanded settings (Strength/Range sliders + Curve for metric rules) -->
					{#if isExpanded && rule.behavior !== InteractionBehavior.Ignore}
						<div class="settings-panel" transition:slide={{ duration: 120, easing: cubicOut }}>
							<div class="slider-row">
								<span class="slider-label">Strength</span>
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
								<span class="slider-label">Range</span>
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

							<!-- Curve editor for metric rules (part of settings) -->
							{#if isMetricRule}
								<div class="curve-section">
									<div class="curve-header">
										<span class="curve-title">Response Curve</span>
										<span class="curve-hint">X: metric → Y: strength</span>
									</div>
									<CurveEditor
										points={rule.curve ?? [{ x: 0, y: 0 }, { x: 1, y: 1 }]}
										onPointsChange={(points) => handleCurveChange(ruleIndex, points)}
									/>
								</div>
							{/if}
						</div>
					{/if}
				</div>
			{/each}
		</div>

		<!-- Add rule buttons -->
		{#if canAddMoreRules()}
			<div class="add-rule-buttons">
				{#if canAddMoreSpeciesRules()}
					<button
						class="add-rule-btn"
						onclick={handleAddSpeciesRule}
					>
						<Plus size={10} strokeWidth={2} />
						<span>Species Rule</span>
					</button>
				{/if}
				<button
					class="add-rule-btn"
					class:disabled={!canAddMoreMetricRules}
					onclick={canAddMoreMetricRules ? handleAddMetricRule : undefined}
					title={canAddMoreMetricRules ? "" : `Max ${MAX_METRIC_RULES_PER_SPECIES} metric rules`}
				>
					<Plus size={10} strokeWidth={2} />
					<span>Metric Rule</span>
				</button>
			</div>
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

	/* Push settings and delete buttons to the right */
	.rule-actions {
		display: flex;
		align-items: center;
		gap: 4px;
		margin-left: auto;
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
		padding: 8px 10px 10px;
		border-top: 1px solid rgba(255, 255, 255, 0.05);
		background: rgba(0, 0, 0, 0.15);
	}

	.slider-row {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 3px 0;
	}

	.slider-label {
		width: 52px;
		flex-shrink: 0;
		font-size: 11px;
		color: rgba(255, 255, 255, 0.6);
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
		width: 36px;
		flex-shrink: 0;
		text-align: right;
		font-family: ui-monospace, monospace;
		font-size: 11px;
		color: rgba(255, 255, 255, 0.6);
	}

	/* Add rule buttons */
	.add-rule-buttons {
		display: flex;
		gap: 6px;
		margin-top: 6px;
	}

	.add-rule-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 4px;
		padding: 6px 10px;
		flex: 1;
		background: rgba(255, 255, 255, 0.02);
		border: 1px dashed rgba(255, 255, 255, 0.12);
		border-radius: 6px;
		cursor: pointer;
		transition: all 0.15s;
		color: rgba(255, 255, 255, 0.4);
	}

	.add-rule-btn span {
		font-size: 9px;
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.add-rule-btn:hover:not(.disabled) {
		background: rgba(99, 102, 241, 0.1);
		border-color: rgba(99, 102, 241, 0.3);
		color: rgba(99, 102, 241, 0.9);
	}

	.add-rule-btn.disabled {
		opacity: 0.35;
		cursor: not-allowed;
	}

	/* Metric rule styling */
	.rule-row.metric-rule {
		border-color: rgba(167, 139, 250, 0.15);
		background: rgba(167, 139, 250, 0.03);
	}

	.metric-of {
		font-size: 9px;
		color: rgba(255, 255, 255, 0.35);
		flex-shrink: 0;
	}

	/* Labeled dropdown menu (for metric source, role) - scrollable like hue dropdown */
	.dropdown-menu.labeled-menu {
		display: flex;
		flex-direction: column;
		width: 120px;
		max-height: 160px;
		overflow-y: auto;
		padding: 4px;
	}

	.dropdown-item.labeled-item {
		display: flex;
		align-items: center;
		justify-content: flex-start;
		gap: 6px;
		padding: 5px 8px;
		font-size: 10px;
		flex-shrink: 0;
		text-align: left;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.dropdown-item.labeled-item span {
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.menu-icon {
		width: 14px;
		height: 14px;
		flex-shrink: 0;
	}

	/* Curve section inside settings panel */
	.curve-section {
		margin-top: 10px;
		padding-top: 10px;
		border-top: 1px solid rgba(255, 255, 255, 0.05);
	}

	.curve-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 6px;
	}

	.curve-title {
		font-size: 10px;
		font-weight: 500;
		color: rgba(255, 255, 255, 0.5);
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.curve-hint {
		font-size: 8px;
		color: rgba(255, 255, 255, 0.3);
	}

</style>
