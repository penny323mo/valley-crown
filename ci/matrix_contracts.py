"""Exact label/check/dimension contracts for the two already prepared fixtures."""
KINDS = ('villager', 'spearman', 'archer', 'scout')
OBSTACLES = ('pine-cutout', 'oak-cutout', 'house-opaque', 'procedural-rock-opaque')
SUFFIXES = (' framebuffer saved', ' real framebuffer', ' sidecar opened')


def schema(mode):
    frames, checks, critical = [], [], []
    def check(name, fatal=False):
        checks.append(name)
        if fatal: critical.append(name)
    def capture(label, size):
        frames.append({'label': label, 'framebuffer': size})
        for suffix in SUFFIXES: check(label + suffix, True)
    def pair(label, size):
        capture(label + '-off', size); capture(label + '-on', size)
    if mode == 'occlusion_matrix':
        size = [390, 600]
        check('Compatibility renderer', True)
        for kind in KINDS:
            check(kind + ' matrix bound', True)
            for clip in ('idle', 'walk', 'attack'):
                pair(kind + '-' + clip + '-unoccluded', size)
                check(kind + ' ' + clip + ' original pixels exact')
        check('spearman matrix bound', True)
        for label in OBSTACLES:
            pair(label, size); capture(label + '-object-only', size)
            for suffix in (' produces silhouette', ' nonvacuous partial coverage', ' preserves normally visible limbs', ' no alpha accumulation stripes'):
                check(label + suffix)
        pair('object-behind-unit', size); check('object behind unit leaves original exact')
        for name in ('empty-reference', 'unit-a-reference', 'unit-b-reference'):
            capture('temporal-' + name, size)
        check('temporal source footprints are nonempty and actually moved')
        capture('temporal-a-visible-mask-written', size); check('temporal initial normal pixels exact')
        for name in ('b-fully-occluded-on', 'b-fully-occluded-off', 'wall-only'):
            capture('temporal-' + name, size)
        for name in ('full occlusion is genuinely complete and nonempty', 'full silhouette has exactly the whole moving unit footprint', 'full silhouette stays one color'):
            check(name)
        capture('temporal-return-a-fully-occluded', size); check('A to B to A has no stale stencil holes')
        capture('temporal-b-visible-again', size); check('moving out of cover restores original texture exactly')
        capture('temporal-all-units-hidden', size); check('empty frame leaves no moving silhouette trail')
        capture('temporal-occluded-after-empty-frame', size); check('empty frame clears previous visibility mask')
        check('overlap second rig bound', True)
        pair('overlapping-units', size); check('overlapping observed units unchanged without world obstacle')
        for step in (1, -1):
            pair('moving-overlap-' + str(step), size); check('moving overlapping unit pixels exact ' + str(step))
        pair('animated-source-local-trs', size); check('animated source mesh and overlay stay pixel-aligned')
        capture('source-tool-hidden', size); capture('source-tool-absent-reference', size)
        check('hidden tool geometry cannot leave overlay')
        capture('corpse-overlay-off', size); capture('corpse-reenable-denied', size)
        check('corpse toggle cannot restore silhouette')
        for count in (1, 12, 24):
            for i in range(count): check('cost fixture rig ' + str(i) + ' bound for ' + str(count), True)
            pair('cost-' + str(count), size); check('bounded measured draw increase at ' + str(count) + ' units')
        kind, total, launch, timing = 'native_controlled_occlusion_matrix', 67, [390, 600], 'settled_two_process_frames_then_post_draw'
    elif mode == 'occlusion_lifecycle':
        check('extra fixture source identity recorded', True)
        check('Compatibility renderer', True); check('viewport fixture supports exact rig', True)
        for index, size in enumerate(([390, 844], [844, 390], [390, 600], [390, 844])):
            prefix = 'resize-' + str(index)
            capture(prefix + '-empty', size); check(prefix + ' exact requested framebuffer', True)
            capture(prefix + '-normal-off', size); capture(prefix + '-normal-on', size)
            check(prefix + ' nonempty normal mesh unchanged')
            for name in ('covered-on', 'covered-off', 'wall-only'): capture(prefix + '-' + name, size)
            check(prefix + ' full coverage verified'); check(prefix + ' no stale resized stencil footprint')
            capture(prefix + '-normal-restored', size); check(prefix + ' original pixels restored')
        size = [390, 844]
        check('overlay copies source camera layer exactly')
        capture('camera-layer-excluded-unit', size); capture('camera-layer-excluded-reference', size)
        check('camera culling source cannot leave silhouette')
        capture('camera-layer-included-unit', size); check('same layer becomes visible when camera allows it')
        for name in ('original-unit', 'empty-reference', 'unit-off', 'unit-on'): capture('clip-' + name, size)
        check('near clip actually cuts a nonempty unit'); check('near clipped source pixels remain exact')
        capture('observation-absent-reference', size); capture('observation-visible-enemy-behind-wall', size)
        check('currently observed enemy silhouette is nonempty')
        capture('observation-enemy-enters-fog', size); check('record removal leaves no fog-hidden silhouette')
        capture('observation-enemy-reappears', size); check('reappearance is fresh and exactly same legal pose')
        capture('observation-unwitnessed-death', size); check('unwitnessed death never draws')
        capture('observation-witnessed-corpse-behind-wall', size); check('corpse behind wall has no xray')
        capture('observation-corpse-enters-fog', size); check('fog removes witnessed enemy corpse')
        kind, total, launch, timing = 'native_controlled_occlusion_lifecycle', 42, [390, 844], 'first_post_draw_after_state_change'
    else:
        raise ValueError('Unreviewed matrix mode')
    assert len(frames) == total and len({row['label'] for row in frames}) == total
    empty_labels = {'temporal-empty-reference', 'temporal-wall-only', 'temporal-all-units-hidden',
                    'source-tool-absent-reference', 'camera-layer-excluded-reference', 'clip-empty-reference',
                    'observation-absent-reference', 'observation-enemy-enters-fog', 'observation-unwitnessed-death', 'observation-corpse-enters-fog'}
    for row in frames:
        label = row['label']
        count = 1
        if label in empty_labels or label.endswith('-object-only') or label.startswith('resize-') and label.endswith(('-empty', '-wall-only')): count = 0
        elif label.startswith(('overlapping-units-', 'moving-overlap-')): count = 2
        elif label.startswith('cost-'): count = int(label.split('-')[1])
        row['visible_rig_count'] = count
    return {'capture_contract': {'mode': mode, 'kind': kind, 'frame_count': total},
            'frames': frames, 'checks': checks, 'critical_checks': critical,
            'launch_framebuffer': launch, 'capture_timing': timing}
