"""Source-only wiring/layout contract; not Godot/runtime/browser validation."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class MenuSourceContract(unittest.TestCase):
    def test_entry_and_deliberate_start(self):
        project = (ROOT / 'project.godot').read_text()
        menu = (ROOT / 'scripts/main_menu.gd').read_text()
        self.assertIn('run/main_scene="res://main_menu.tscn"', project)
        ready = menu.split('func _ready():', 1)[1].split('func _layout', 1)[0]
        self.assertNotIn('instantiate()', ready)
        self.assertEqual(menu.count('MATCH_SCENE.instantiate()'), 1)
        self.assertIn('"StartMatchButton", _start_match', menu)
        self.assertIn('call_deferred("_replace_match")', menu)
    def test_pause_and_terminal_wiring(self):
        menu = (ROOT / 'scripts/main_menu.gd').read_text()
        game = (ROOT / 'scripts/game.gd').read_text()
        for token in ['match_node.paused = true', 'Node.PROCESS_MODE_DISABLED', 'match_node.ui.hide()', 'match_node._toggle_pause()', '"CancelNewMatchButton"', 'match_node.game_over: return']:
            self.assertIn(token, menu)
        for token in ['signal main_menu_requested', 'signal restart_requested', '_button("主選單", _request_main_menu', '_button("再開一局", _request_restart)']:
            self.assertIn(token, game)
    def test_small_viewport_geometry_and_scroll(self):
        menu = (ROOT / 'scripts/main_menu.gd').read_text()
        # Source arithmetic only; actual rendered geometry is a separate gate.
        for w, h in [(320,568),(390,844),(844,390),(568,320),(1440,900)]:
            wide = w >= 640 and w > h * 1.15
            margin = 28 if w >= 360 else 20
            card_w = min(390 if wide else 440, max(1,w-2*margin))
            x = max(32,w*.075) if wide else (w-card_w)*.5
            for count in (2,3):
                card_h = 54*count + 10*max(0,count-1) + 104
                y = max(16,h-card_h-28)
                self.assertGreaterEqual(x,16)
                self.assertGreaterEqual(y,16)
                self.assertLessEqual(x+card_w,w-16)
                self.assertLessEqual(y+card_h,h-16)
        self.assertIn('button.custom_minimum_size.y = 54',menu)
        self.assertIn('card_column.add_child(buttons)',menu)
        self.assertNotIn('box.add_child(buttons)',menu)
        self.assertIn('scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO',menu)
        self.assertIn('TextServer.AUTOWRAP_WORD_SMART',menu)
    def test_cancel_and_drag_are_not_clicks(self):
        menu = (ROOT / 'scripts/main_menu.gd').read_text()
        self.assertIn('event.position.distance_to(press.origin) <= 12.0 and press.button == button',menu)
        self.assertIn('distance_to(touch_presses[event.index].origin) > 12.0',menu)
        self.assertIn("window.addEventListener('touchcancel'",menu)
    def test_interrupted_touch_wiring(self):
        menu = (ROOT / 'scripts/main_menu.gd').read_text()
        self.assertIn('active_touches.size() > 1: _cancel_menu_touches()', menu)
        self.assertIn('func _layout():\n\t_cancel_menu_touches()', menu)
        self.assertIn('page = next_page\n\t_cancel_menu_touches()', menu)
        self.assertIn('event.position.distance_to(press.origin) <= 12.0', menu)
    def test_entry_scene_is_hashed(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('menu_runtime_manifest', ROOT / 'tools/runtime_manifest.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertIn(ROOT / 'main_menu.tscn', module.runtime_paths(ROOT))
    def test_menu_font_coverage(self):
        from fontTools.ttLib import TTFont
        cmap = TTFont(ROOT / 'assets/fonts/ui_tc.otf').getBestCmap()
        source = (ROOT / 'scripts/main_menu.gd').read_text()
        self.assertEqual(sorted({c for c in source if ord(c) > 127 and ord(c) not in cmap}), [])
if __name__ == '__main__': unittest.main()
