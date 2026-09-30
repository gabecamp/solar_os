"""
The main gameplay state: hex-grid overworld, movement, fog of war, and
the NEO Scavenger-style UI chrome (needs bars, action buttons, log).

ESC saves and returns to the main menu. F5 saves without leaving.
"""

import pygame
from constants import (
    SCREEN_W, SCREEN_H, HEX_SIZE, TERRAIN,
    BG_COLOR, GRID_LINE_COLOR, PLAYER_COLOR, HOVER_COLOR,
    REACHABLE_COLOR, NO_MP_COLOR, FOG_UNSEEN_COLOR, EXPLORED_SHADE,
    REST_HOURS, LEFT_PANEL_W, RIGHT_PANEL_W, BOTTOM_PANEL_H,
    PANEL_BG, PANEL_BORDER, TEXT_COLOR, DIM_TEXT,
    ACTION_BUTTONS, ICON_BUTTONS, NEEDS, TILE_DEPTH,
)
from hexmath import axial_to_iso, iso_to_axial, hex_top_corners, shade, axial_distance, neighbors_of
from ui_widgets import draw_bar
from ui_panels import draw_needs_sidebar
import save_load
import needs as needs_system


class OverworldState:
    def __init__(self, manager, player, tiles, ground_items=None):
        self.manager = manager
        self.player = player
        self.tiles = tiles
        self.ground_items = ground_items if ground_items is not None else {}

        self.font = pygame.font.SysFont(None, 16)
        self.small_font = pygame.font.SysFont(None, 13)
        self.big_font = pygame.font.SysFont(None, 20, bold=True)

        self.hover_hex = None
        self.log = [f"{player.name} enters the wasteland."]

        self.map_rect = pygame.Rect(
            LEFT_PANEL_W, 0,
            SCREEN_W - LEFT_PANEL_W - RIGHT_PANEL_W,
            SCREEN_H - BOTTOM_PANEL_H,
        )
        self.origin_x = self.map_rect.x + self.map_rect.w // 2
        self.origin_y = self.map_rect.y + self.map_rect.h // 2

        self.draw_order = sorted(self.tiles.keys(), key=lambda pos: self.hex_to_screen(*pos)[1])

        if not self.player.explored:
            self.update_visibility()
        else:
            self.player.visible = {
                pos for pos in self.tiles
                if axial_distance(self.player.player_pos, pos) <= self.player.sight
            }

        self.action_button_rects = []
        self.icon_button_rects = []
        self.end_turn_rect = pygame.Rect(SCREEN_W - 130, 8, 110, 30)
        self.main_menu_rect = pygame.Rect(10, 8, 130, 30)

    # -- messaging -----------------------------------------------------

    def set_message(self, text):
        self.log.append(text)
        self.log = self.log[-6:]

    # -- coordinate helpers -------------------------------------------------

    def hex_to_screen(self, q, r):
        x, y = axial_to_iso(q, r, HEX_SIZE)
        return self.origin_x + x, self.origin_y + y

    def screen_to_hex(self, sx, sy):
        return iso_to_axial(sx - self.origin_x, sy - self.origin_y, HEX_SIZE)

    def update_visibility(self):
        p = self.player
        p.visible = {pos for pos in self.tiles if axial_distance(p.player_pos, pos) <= p.sight}
        p.explored |= p.visible

    # -- game logic -----------------------------------------------------

    def try_move(self, target):
        p = self.player
        if target not in self.tiles:
            return
        if target not in neighbors_of(p.player_pos, self.tiles):
            self.set_message("That hex isn't adjacent.")
            return
        terrain = self.tiles[target]
        color, cost, passable = TERRAIN[terrain]
        if not passable:
            self.set_message(f"Can't cross {terrain} on foot.")
            return
        if p.mp <= 0:
            self.set_message("Out of movement points. Rest to recover.")
            return
        p.mp -= cost
        p.player_pos = target
        p.game_hours += cost
        needs_system.apply_awake_hours(p, cost)
        self.update_visibility()
        mp_note = f"{p.mp}/{p.max_mp} MP" if p.mp >= 0 else f"{p.mp} MP (overexerted!)"
        self.set_message(f"Moved to {terrain}. (cost {cost} MP, +{cost}h) — {mp_note}")
        for warning in needs_system.critical_warnings(p):
            self.set_message(warning)

    def move_towards_direction(self, dx, dy):
        import math
        p = self.player
        best, best_dot = None, -999
        px, py = self.hex_to_screen(*p.player_pos)
        for n in neighbors_of(p.player_pos, self.tiles):
            nx, ny = self.hex_to_screen(*n)
            vx, vy = nx - px, ny - py
            length = math.hypot(vx, vy) or 1
            dot = (vx / length) * dx + (vy / length) * dy
            if dot > best_dot:
                best_dot, best = dot, n
        if best:
            self.try_move(best)

    def rest(self):
        p = self.player
        effective_cap = p.effective_max_mp()
        if p.mp >= effective_cap:
            self.set_message("Already at full movement points.")
            return
        p.game_hours += REST_HOURS
        needs_system.apply_rest_hours(p, REST_HOURS)
        p.mp = p.effective_max_mp()  # recompute after resting restores some needs
        self.update_visibility()
        self.set_message(f"Rested {REST_HOURS}h. Movement points restored to {p.mp}/{p.max_mp}.")
        for warning in needs_system.critical_warnings(p):
            self.set_message(warning)

    def save(self):
        save_load.save_game(self.player, self.tiles, self.ground_items)
        self.set_message("Game saved.")

    # -- rendering: map -----------------------------------------------------

    def draw_tile_block(self, screen, pos, top_color, outline=None, outline_width=0, draw_sides=True):
        cx, cy = self.hex_to_screen(*pos)
        if not (self.map_rect.x - 60 < cx < self.map_rect.right + 60):
            return
        if not (self.map_rect.y - 60 < cy < self.map_rect.bottom + 60):
            return
        corners = hex_top_corners(cx, cy, HEX_SIZE - 1)

        if draw_sides:
            bottom_idx = max(range(6), key=lambda i: corners[i][1])
            left_idx = (bottom_idx - 1) % 6
            right_idx = (bottom_idx + 1) % 6

            def lower(pt):
                return (pt[0], pt[1] + TILE_DEPTH)

            right_face = [corners[bottom_idx], corners[right_idx],
                          lower(corners[right_idx]), lower(corners[bottom_idx])]
            pygame.draw.polygon(screen, shade(top_color, 0.55), right_face)

            left_face = [corners[bottom_idx], corners[left_idx],
                         lower(corners[left_idx]), lower(corners[bottom_idx])]
            pygame.draw.polygon(screen, shade(top_color, 0.4), left_face)

        pygame.draw.polygon(screen, top_color, corners)
        pygame.draw.polygon(screen, GRID_LINE_COLOR, corners, 1)

        if outline:
            pygame.draw.polygon(screen, outline, corners, outline_width)

    def draw_map(self, screen):
        p = self.player
        screen.set_clip(self.map_rect)
        screen.fill(BG_COLOR, self.map_rect)
        reachable = set(neighbors_of(p.player_pos, self.tiles))

        for pos in self.draw_order:
            terrain = self.tiles[pos]
            color, cost, passable = TERRAIN[terrain]

            if pos in p.visible:
                outline, outline_w = None, 0
                if pos in reachable and passable:
                    outline, outline_w = (REACHABLE_COLOR if p.mp > 0 else NO_MP_COLOR), 3
                if pos == self.hover_hex:
                    outline, outline_w = HOVER_COLOR, 2
                self.draw_tile_block(screen, pos, color, outline, outline_w, draw_sides=True)
            elif pos in p.explored:
                self.draw_tile_block(screen, pos, shade(color, EXPLORED_SHADE), draw_sides=False)
            else:
                self.draw_tile_block(screen, pos, FOG_UNSEEN_COLOR, draw_sides=False)
                continue

            if pos == p.player_pos:
                px, py = self.hex_to_screen(*pos)
                pygame.draw.circle(screen, (0, 0, 0), (int(px), int(py) - 6), HEX_SIZE // 2 + 2)
                pygame.draw.circle(screen, PLAYER_COLOR, (int(px), int(py) - 8), HEX_SIZE // 2)

        screen.set_clip(None)

    # -- rendering: UI chrome -----------------------------------------------

    def draw_left_panel(self, screen):
        p = self.player
        y = draw_needs_sidebar(screen, p, self.font, self.small_font, self.main_menu_rect)

        # small equipped-gear preview strip (open the CHAR/inventory screen for the full view)
        slot_size = 46
        for i in range(4):
            sx = 12 + (i % 2) * (slot_size + 8)
            sy = y + (i // 2) * (slot_size + 8)
            r = pygame.Rect(sx, sy, slot_size, slot_size)
            pygame.draw.rect(screen, (30, 30, 30), r)
            pygame.draw.rect(screen, PANEL_BORDER, r, 1)

    def draw_right_panel(self, screen):
        rect = pygame.Rect(SCREEN_W - RIGHT_PANEL_W, 0, RIGHT_PANEL_W, SCREEN_H)
        pygame.draw.rect(screen, PANEL_BG, rect)
        pygame.draw.line(screen, PANEL_BORDER, (rect.x, 0), (rect.x, SCREEN_H), 2)

        pygame.draw.rect(screen, (40, 130, 60), self.end_turn_rect)
        pygame.draw.rect(screen, PANEL_BORDER, self.end_turn_rect, 1)
        surf = self.font.render("END TURN", True, (255, 255, 255))
        screen.blit(surf, (self.end_turn_rect.x + 8, self.end_turn_rect.y + 7))

        y = 50
        self.action_button_rects = []
        for label, color in ACTION_BUTTONS:
            r = pygame.Rect(rect.x + 12, y, RIGHT_PANEL_W - 24, 32)
            pygame.draw.rect(screen, color, r)
            pygame.draw.rect(screen, (0, 0, 0), r, 1)
            surf = self.small_font.render(label, True, (20, 20, 20))
            screen.blit(surf, (r.x + (r.w - surf.get_width()) // 2, r.y + 9))
            self.action_button_rects.append((r, label))
            y += 40

        y += 15
        self.icon_button_rects = []
        for label in ICON_BUTTONS:
            r = pygame.Rect(rect.x + 12, y, RIGHT_PANEL_W - 24, 40)
            pygame.draw.rect(screen, (35, 35, 35), r)
            pygame.draw.rect(screen, PANEL_BORDER, r, 1)
            surf = self.small_font.render(label, True, DIM_TEXT)
            screen.blit(surf, (r.x + (r.w - surf.get_width()) // 2, r.y + 13))
            self.icon_button_rects.append((r, label))
            y += 48

    def draw_bottom_panel(self, screen):
        rect = pygame.Rect(0, SCREEN_H - BOTTOM_PANEL_H, SCREEN_W, BOTTOM_PANEL_H)
        pygame.draw.rect(screen, PANEL_BG, rect)
        pygame.draw.line(screen, PANEL_BORDER, (0, rect.y), (SCREEN_W, rect.y), 2)

        log_rect = pygame.Rect(rect.x + 10, rect.y + 10, int(SCREEN_W * 0.62), BOTTOM_PANEL_H - 20)
        pygame.draw.rect(screen, (12, 12, 12), log_rect)
        pygame.draw.rect(screen, PANEL_BORDER, log_rect, 1)
        ly = log_rect.y + 6
        for line in self.log:
            surf = self.small_font.render(line, True, TEXT_COLOR)
            screen.blit(surf, (log_rect.x + 8, ly))
            ly += 18

        combat_rect = pygame.Rect(log_rect.right + 15, rect.y + 10,
                                   SCREEN_W - (log_rect.right + 15) - 10, BOTTOM_PANEL_H - 20)
        pygame.draw.rect(screen, (12, 12, 12), combat_rect)
        pygame.draw.rect(screen, PANEL_BORDER, combat_rect, 1)
        surf = self.small_font.render("No target selected", True, DIM_TEXT)
        screen.blit(surf, (combat_rect.x + 10, combat_rect.y + 10))

    def draw_top_status(self, screen):
        p = self.player
        terrain = self.tiles.get(p.player_pos, "?")
        text = f"{p.name} | Pos {p.player_pos} | {terrain} | Sight {p.sight} | {p.game_hours:.0f}h"
        surf = self.small_font.render(text, True, DIM_TEXT)
        screen.blit(surf, (self.map_rect.x + 8, 8))

    def draw(self, screen):
        screen.fill(BG_COLOR)
        self.draw_map(screen)
        self.draw_left_panel(screen)
        self.draw_right_panel(screen)
        self.draw_bottom_panel(screen)
        self.draw_top_status(screen)

    # -- UI click handling -----------------------------------------------

    def handle_ui_click(self, pos):
        if self.end_turn_rect.collidepoint(pos):
            self.rest()
            return True
        if self.main_menu_rect.collidepoint(pos):
            self.save()
            from state_main_menu import MainMenuState
            self.manager.change_state(MainMenuState(self.manager))
            return True
        for r, label in self.action_button_rects:
            if r.collidepoint(pos):
                self.set_message(f"{label} isn't wired up yet — placeholder button.")
                return True
        for r, label in self.icon_button_rects:
            if r.collidepoint(pos):
                if label == "CHAR":
                    self.open_inventory()
                else:
                    self.set_message(f"{label} screen isn't built yet — placeholder button.")
                return True
        return False

    def open_inventory(self):
        from state_inventory import InventoryState
        self.manager.change_state(InventoryState(self.manager, self))

    # -- state interface -----------------------------------------------------

    def handle_event(self, event):
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.save()
                from state_main_menu import MainMenuState
                self.manager.change_state(MainMenuState(self.manager))
            elif event.key == pygame.K_F5:
                self.save()
            elif event.key in (pygame.K_UP, pygame.K_w):
                self.move_towards_direction(0, -1)
            elif event.key in (pygame.K_DOWN, pygame.K_s):
                self.move_towards_direction(0, 1)
            elif event.key in (pygame.K_LEFT, pygame.K_a):
                self.move_towards_direction(-1, 0)
            elif event.key in (pygame.K_RIGHT, pygame.K_d):
                self.move_towards_direction(1, 0)
            elif event.key == pygame.K_SPACE:
                self.rest()
            elif event.key == pygame.K_i:
                self.open_inventory()
        elif event.type == pygame.MOUSEMOTION:
            if self.map_rect.collidepoint(event.pos):
                self.hover_hex = self.screen_to_hex(*event.pos)
            else:
                self.hover_hex = None
        elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if not self.handle_ui_click(event.pos):
                if self.map_rect.collidepoint(event.pos):
                    target = self.screen_to_hex(*event.pos)
                    self.try_move(target)

    def update(self):
        pass
