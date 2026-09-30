"""
Inventory & equipment screen.

Body slots: head, ears, eyes, neck, shirt, jacket, hands, wrists, pants, feet.

Interaction model (simplified two-click transfer):
  - Click an item slot (ground / backpack / equip) to select it as the source.
  - Click a destination slot to move the item there. Equipping only
    succeeds if the item's slot matches the destination slot.
  - CONSUME mode: click any consumable item to eat/drink it immediately.

TAKE/DROP and MOVE modes currently behave identically (both do a generic
transfer) — NEO Scavenger distinguishes them more finely than this
prototype does. WHOLE STACK is a visual toggle only for now.
"""

import pygame
from constants import (
    SCREEN_W, SCREEN_H, LEFT_PANEL_W, BOTTOM_PANEL_H,
    PANEL_BG, PANEL_BORDER, TEXT_COLOR, DIM_TEXT, ACCENT_COLOR,
)
from items import ITEM_DB, EQUIP_SLOTS, BACKPACK_CAPACITY
from ui_panels import draw_needs_sidebar
import save_load

MODES = ["TAKE/DROP", "MOVE", "CONSUME"]

GROUND_COLS, GROUND_ROWS = 6, 4
BACKPACK_COLS, BACKPACK_ROWS = 5, 5


class InventoryState:
    def __init__(self, manager, overworld):
        self.manager = manager
        self.overworld = overworld  # keep a reference so we can return to it intact
        self.player = overworld.player
        self.tiles = overworld.tiles
        self.ground_items = overworld.ground_items

        self.font = pygame.font.SysFont(None, 16)
        self.small_font = pygame.font.SysFont(None, 13)
        self.big_font = pygame.font.SysFont(None, 20, bold=True)

        self.mode = "TAKE/DROP"
        self.whole_stack = False
        self.selected = None  # (kind, index_or_slot) or None

        self.main_menu_rect = pygame.Rect(10, 8, 130, 30)
        self.map_btn_rect = pygame.Rect(SCREEN_W - 150, 4, 130, 26)

        self.mode_rects = []
        self.whole_stack_rect = pygame.Rect(0, 0, 1, 1)
        self.ground_rects = []
        self.inventory_rects = []
        self.equip_rects = []

        self.log = ["Inventory opened."]

    # -- helpers -----------------------------------------------------

    def set_message(self, text):
        self.log.append(text)
        self.log = self.log[-6:]

    def ground_list(self):
        return self.ground_items.setdefault(self.player.player_pos, [])

    def get_stack(self, kind, key):
        if kind == "ground":
            gl = self.ground_list()
            return gl[key] if 0 <= key < len(gl) else None
        if kind == "inventory":
            inv = self.player.inventory
            return inv[key] if 0 <= key < len(inv) else None
        if kind == "equip":
            item_id = self.player.equipped.get(key)
            return {"item_id": item_id, "qty": 1} if item_id else None
        return None

    def remove_stack(self, kind, key):
        if kind == "ground":
            return self.ground_list().pop(key)
        if kind == "inventory":
            return self.player.inventory.pop(key)
        if kind == "equip":
            item_id = self.player.equipped[key]
            self.player.equipped[key] = None
            return {"item_id": item_id, "qty": 1}
        return None

    def put_stack(self, kind, key, stack, validate=True):
        """Returns True on success. On failure the caller must restore the
        stack to wherever it came from."""
        if kind == "ground":
            self.ground_list().append(stack)
            return True
        if kind == "inventory":
            if len(self.player.inventory) >= BACKPACK_CAPACITY:
                self.set_message("Backpack is full.")
                return False
            self.player.inventory.append(stack)
            return True
        if kind == "equip":
            slot = key
            item_def = ITEM_DB[stack["item_id"]]
            if validate and item_def["slot"] != slot:
                self.set_message(f"{item_def['name']} can't go in the {slot} slot.")
                return False
            current = self.player.equipped[slot]
            if current:
                # bump whatever was equipped back into the backpack
                if len(self.player.inventory) >= BACKPACK_CAPACITY:
                    self.set_message("Backpack is full — can't swap that out.")
                    return False
                self.player.inventory.append({"item_id": current, "qty": 1})
            self.player.equipped[slot] = stack["item_id"]
            return True
        return False

    def try_transfer(self, source, dest):
        s_kind, s_key = source
        d_kind, d_key = dest
        if source == dest:
            self.selected = None
            return
        stack = self.remove_stack(s_kind, s_key)
        if stack is None or stack.get("item_id") is None:
            return
        ok = self.put_stack(d_kind, d_key, stack)
        if not ok:
            # revert
            self.put_stack(s_kind, s_key, stack, validate=False)
        else:
            item_name = ITEM_DB[stack["item_id"]]["name"]
            self.set_message(f"Moved {item_name}.")

    def try_consume(self, kind, key):
        stack = self.get_stack(kind, key)
        if stack is None:
            return
        item_def = ITEM_DB[stack["item_id"]]
        if not item_def.get("consumable"):
            self.set_message(f"{item_def['name']} isn't something you can consume.")
            return
        for need, amount in item_def["consumable"].items():
            self.player.needs[need] = min(100, self.player.needs[need] + amount)
        self.remove_stack(kind, key)
        self.set_message(f"{self.player.name} consumed {item_def['name']}.")

    def slot_click(self, kind, key):
        if self.mode == "CONSUME":
            self.try_consume(kind, key)
            return
        if self.selected is None:
            if self.get_stack(kind, key) is not None:
                self.selected = (kind, key)
            return
        self.try_transfer(self.selected, (kind, key))
        self.selected = None

    # -- rendering -----------------------------------------------------

    def draw_item_icon(self, screen, rect, stack, selected=False):
        pygame.draw.rect(screen, (28, 28, 28), rect)
        pygame.draw.rect(screen, PANEL_BORDER, rect, 1)
        if stack and stack.get("item_id"):
            item_def = ITEM_DB[stack["item_id"]]
            inner = rect.inflate(-10, -10)
            pygame.draw.rect(screen, item_def["color"], inner)
            if stack.get("qty", 1) > 1:
                qty_surf = self.small_font.render(str(stack["qty"]), True, (255, 255, 255))
                screen.blit(qty_surf, (rect.right - qty_surf.get_width() - 3, rect.bottom - 16))
        if selected:
            pygame.draw.rect(screen, (255, 255, 100), rect, 2)

    def draw(self, screen):
        screen.fill((10, 10, 10))

        y_after_sidebar = draw_needs_sidebar(
            screen, self.player, self.font, self.small_font, self.main_menu_rect
        )

        # -- top mode bar --
        top_rect = pygame.Rect(LEFT_PANEL_W, 0, SCREEN_W - LEFT_PANEL_W, 34)
        pygame.draw.rect(screen, PANEL_BG, top_rect)
        pygame.draw.line(screen, PANEL_BORDER, (LEFT_PANEL_W, 34), (SCREEN_W, 34), 1)

        self.mode_rects = []
        x = LEFT_PANEL_W + 10
        for m in MODES:
            w = 90
            r = pygame.Rect(x, 4, w, 26)
            active = (self.mode == m)
            pygame.draw.rect(screen, ACCENT_COLOR if active else (40, 40, 40), r)
            pygame.draw.rect(screen, PANEL_BORDER, r, 1)
            surf = self.small_font.render(m, True, (10, 10, 10) if active else TEXT_COLOR)
            screen.blit(surf, (r.x + (r.w - surf.get_width()) // 2, r.y + 6))
            self.mode_rects.append((r, m))
            x += w + 8

        self.whole_stack_rect = pygame.Rect(x, 4, 110, 26)
        pygame.draw.rect(screen, (150, 60, 60) if self.whole_stack else (40, 40, 40), self.whole_stack_rect)
        pygame.draw.rect(screen, PANEL_BORDER, self.whole_stack_rect, 1)
        ws_surf = self.small_font.render("WHOLE STACK", True, TEXT_COLOR)
        screen.blit(ws_surf, (self.whole_stack_rect.x + 6, self.whole_stack_rect.y + 6))

        pygame.draw.rect(screen, (40, 130, 60), self.map_btn_rect)
        pygame.draw.rect(screen, PANEL_BORDER, self.map_btn_rect, 1)
        map_surf = self.font.render("BACK TO MAP", True, (255, 255, 255))
        screen.blit(map_surf, (self.map_btn_rect.x + 8, self.map_btn_rect.y + 5))

        # -- ground items grid --
        gx, gy = LEFT_PANEL_W + 10, 44
        label = self.font.render("Items on the ground here", True, TEXT_COLOR)
        screen.blit(label, (gx, gy - 14))
        self.ground_rects = []
        ground = self.ground_list()
        cell, gap = 44, 6
        for i in range(GROUND_COLS * GROUND_ROWS):
            col, row = i % GROUND_COLS, i // GROUND_COLS
            rect = pygame.Rect(gx + col * (cell + gap), gy + row * (cell + gap), cell, cell)
            stack = ground[i] if i < len(ground) else None
            selected = self.selected == ("ground", i) and stack is not None
            self.draw_item_icon(screen, rect, stack, selected)
            self.ground_rects.append((rect, i))

        # -- paperdoll + equip slots --
        px0 = gx + GROUND_COLS * (cell + gap) + 30
        self._draw_silhouette(screen, px0, 60)
        self._draw_equip_slots(screen, px0 + 100, 50)

        # -- backpack grid --
        bx = px0 + 100 + 170
        by = 44
        label = self.font.render(f"Backpack ({len(self.player.inventory)}/{BACKPACK_CAPACITY})", True, TEXT_COLOR)
        screen.blit(label, (bx, by - 14))
        self.inventory_rects = []
        bcell, bgap = 41, 6
        for i in range(BACKPACK_COLS * BACKPACK_ROWS):
            col, row = i % BACKPACK_COLS, i // BACKPACK_COLS
            rect = pygame.Rect(bx + col * (bcell + bgap), by + row * (bcell + bgap), bcell, bcell)
            stack = self.player.inventory[i] if i < len(self.player.inventory) else None
            selected = self.selected == ("inventory", i) and stack is not None
            self.draw_item_icon(screen, rect, stack, selected)
            self.inventory_rects.append((rect, i))

        recipes_y = by + BACKPACK_ROWS * (bcell + bgap) + 10
        recipes_label = self.font.render("Known Recipes", True, TEXT_COLOR)
        screen.blit(recipes_label, (bx, recipes_y))
        none_label = self.small_font.render("(none learned yet)", True, DIM_TEXT)
        screen.blit(none_label, (bx, recipes_y + 18))

        self._draw_bottom_panel(screen)

    def _draw_silhouette(self, screen, x, y):
        pygame.draw.circle(screen, (70, 70, 75), (x + 20, y + 18), 16)
        pygame.draw.rect(screen, (70, 70, 75), (x, y + 36, 40, 90))
        pygame.draw.rect(screen, (60, 60, 65), (x + 2, y + 126, 15, 70))
        pygame.draw.rect(screen, (60, 60, 65), (x + 23, y + 126, 15, 70))

    def _draw_equip_slots(self, screen, x, y):
        self.equip_rects = []
        row_h = 34
        for i, slot in enumerate(EQUIP_SLOTS):
            rect = pygame.Rect(x, y + i * row_h, 26, 26)
            item_id = self.player.equipped.get(slot)
            stack = {"item_id": item_id, "qty": 1} if item_id else None
            selected = self.selected == ("equip", slot) and stack is not None
            self.draw_item_icon(screen, rect, stack, selected)

            item_name = ITEM_DB[item_id]["name"] if item_id else "(empty)"
            label = self.small_font.render(f"{slot}: {item_name}", True, TEXT_COLOR if item_id else DIM_TEXT)
            screen.blit(label, (rect.right + 8, rect.y + 6))

            self.equip_rects.append((rect, slot))

    def _draw_bottom_panel(self, screen):
        rect = pygame.Rect(0, SCREEN_H - BOTTOM_PANEL_H, SCREEN_W, BOTTOM_PANEL_H)
        pygame.draw.rect(screen, PANEL_BG, rect)
        pygame.draw.line(screen, PANEL_BORDER, (0, rect.y), (SCREEN_W, rect.y), 2)

        log_rect = pygame.Rect(rect.x + 10, rect.y + 10, SCREEN_W - 20, BOTTOM_PANEL_H - 20)
        pygame.draw.rect(screen, (12, 12, 12), log_rect)
        pygame.draw.rect(screen, PANEL_BORDER, log_rect, 1)
        ly = log_rect.y + 6
        for line in self.log:
            surf = self.small_font.render(line, True, TEXT_COLOR)
            screen.blit(surf, (log_rect.x + 8, ly))
            ly += 18

    # -- state interface -----------------------------------------------------

    def handle_event(self, event):
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            self._return_to_map()
            return

        if event.type != pygame.MOUSEBUTTONDOWN or event.button != 1:
            return
        pos = event.pos

        if self.map_btn_rect.collidepoint(pos):
            self._return_to_map()
            return
        if self.main_menu_rect.collidepoint(pos):
            save_load.save_game(self.player, self.tiles, self.ground_items)
            from state_main_menu import MainMenuState
            self.manager.change_state(MainMenuState(self.manager))
            return

        for r, m in self.mode_rects:
            if r.collidepoint(pos):
                self.mode = m
                self.selected = None
                return
        if self.whole_stack_rect.collidepoint(pos):
            self.whole_stack = not self.whole_stack
            return

        for r, idx in self.ground_rects:
            if r.collidepoint(pos):
                self.slot_click("ground", idx)
                return
        for r, idx in self.inventory_rects:
            if r.collidepoint(pos):
                self.slot_click("inventory", idx)
                return
        for r, slot in self.equip_rects:
            if r.collidepoint(pos):
                self.slot_click("equip", slot)
                return

    def _return_to_map(self):
        self.overworld.set_message("Closed inventory.")
        self.manager.change_state(self.overworld)

    def update(self):
        pass
