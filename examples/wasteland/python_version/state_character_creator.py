"""
Character creator: NEO Scavenger-style attribute point-buy crossed with
a Project Zomboid-style trait budget (positive traits cost points,
negative traits grant points, net must be >= 0 to confirm).
"""

import pygame
from constants import (
    SCREEN_W, SCREEN_H, MENU_BG, TITLE_COLOR, TEXT_COLOR, DIM_TEXT,
    ACCENT_COLOR, WARN_COLOR,
)
from ui_widgets import Button, TextInput
from traits import (
    ATTRIBUTES, ATTRIBUTE_MIN, ATTRIBUTE_MAX, ATTRIBUTE_DEFAULT,
    ATTRIBUTE_POINTS_TOTAL, POSITIVE_TRAITS, NEGATIVE_TRAITS,
)
from player import Player


class CharacterCreatorState:
    def __init__(self, manager):
        self.manager = manager
        self.font = pygame.font.SysFont(None, 18)
        self.small_font = pygame.font.SysFont(None, 15)
        self.title_font = pygame.font.SysFont(None, 30, bold=True)

        self.name_input = TextInput((30, 46, 260, 32), text="Survivor")

        self.attributes = {a: ATTRIBUTE_DEFAULT for a in ATTRIBUTES}
        self.selected_traits = set()

        self.attr_rects = {}
        y = 150
        for a in ATTRIBUTES:
            minus_rect = pygame.Rect(30, y, 26, 26)
            plus_rect = pygame.Rect(30 + 26 + 90, y, 26, 26)
            self.attr_rects[a] = (minus_rect, plus_rect)
            y += 38

        self.positive_rects = {}
        y = 90
        for t in POSITIVE_TRAITS:
            self.positive_rects[t["name"]] = pygame.Rect(360, y, 300, 42)
            y += 48

        self.negative_rects = {}
        y = 90
        for t in NEGATIVE_TRAITS:
            self.negative_rects[t["name"]] = pygame.Rect(690, y, 300, 42)
            y += 48

        self.back_btn = Button((30, SCREEN_H - 56, 110, 36), "Back")
        self.confirm_btn = Button((SCREEN_W - 190, SCREEN_H - 56, 160, 36), "Confirm & Start")

        self.warning = ""

    # -- derived values -------------------------------------------------

    def attribute_pool_remaining(self):
        return ATTRIBUTE_POINTS_TOTAL - sum(self.attributes.values())

    def trait_points_remaining(self):
        total = 0
        for t in POSITIVE_TRAITS:
            if t["name"] in self.selected_traits:
                total -= t["cost"]
        for t in NEGATIVE_TRAITS:
            if t["name"] in self.selected_traits:
                total += t["cost"]
        return total

    # -- events -----------------------------------------------------

    def handle_event(self, event):
        self.name_input.handle_event(event)

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos

            for a, (minus_rect, plus_rect) in self.attr_rects.items():
                if minus_rect.collidepoint(pos) and self.attributes[a] > ATTRIBUTE_MIN:
                    self.attributes[a] -= 1
                elif plus_rect.collidepoint(pos) and self.attributes[a] < ATTRIBUTE_MAX \
                        and self.attribute_pool_remaining() > 0:
                    self.attributes[a] += 1

            for name, rect in self.positive_rects.items():
                if rect.collidepoint(pos):
                    self._toggle_trait(name)
            for name, rect in self.negative_rects.items():
                if rect.collidepoint(pos):
                    self._toggle_trait(name)

            if self.back_btn.clicked(pos):
                from state_main_menu import MainMenuState
                self.manager.change_state(MainMenuState(self.manager))

            if self.confirm_btn.clicked(pos):
                self._try_confirm()

    def _toggle_trait(self, name):
        if name in self.selected_traits:
            self.selected_traits.discard(name)
        else:
            self.selected_traits.add(name)

    def _try_confirm(self):
        if not self.name_input.text.strip():
            self.warning = "Enter a name first."
            return
        if self.trait_points_remaining() < 0:
            self.warning = "You've spent more trait points than you have — remove a trait or add a flaw."
            return

        player = Player(
            name=self.name_input.text.strip(),
            attributes=dict(self.attributes),
            trait_names=list(self.selected_traits),
        )
        from mapgen import generate_map, generate_ground_items
        tiles = generate_map()
        ground_items = generate_ground_items(tiles)

        from state_overworld import OverworldState
        self.manager.change_state(OverworldState(self.manager, player, tiles, ground_items))

    def update(self):
        pass

    # -- drawing -----------------------------------------------------

    def draw(self, screen):
        screen.fill(MENU_BG)
        title = self.title_font.render("Create Your Survivor", True, TITLE_COLOR)
        screen.blit(title, (30, 10))

        name_label = self.small_font.render("Name:", True, TEXT_COLOR)
        screen.blit(name_label, (30, 30))
        self.name_input.draw(screen, self.font)

        self._draw_attributes(screen)
        self._draw_trait_column(screen, "Positive Traits", POSITIVE_TRAITS, self.positive_rects, ACCENT_COLOR)
        self._draw_trait_column(screen, "Negative Traits (Flaws)", NEGATIVE_TRAITS, self.negative_rects, WARN_COLOR)

        trait_pts = self.trait_points_remaining()
        color = ACCENT_COLOR if trait_pts >= 0 else WARN_COLOR
        pts_surf = self.font.render(f"Trait points remaining: {trait_pts}", True, color)
        screen.blit(pts_surf, (360, SCREEN_H - 90))

        if self.warning:
            warn_surf = self.small_font.render(self.warning, True, WARN_COLOR)
            screen.blit(warn_surf, (360, SCREEN_H - 66))

        mouse_pos = pygame.mouse.get_pos()
        self.back_btn.draw(screen, self.font, hovered=self.back_btn.rect.collidepoint(mouse_pos))
        self.confirm_btn.color = ACCENT_COLOR if trait_pts >= 0 else None
        self.confirm_btn.draw(screen, self.font, hovered=self.confirm_btn.rect.collidepoint(mouse_pos))

    def _draw_attributes(self, screen):
        header = self.font.render("Attributes", True, TITLE_COLOR)
        screen.blit(header, (30, 120))

        for a in ATTRIBUTES:
            minus_rect, plus_rect = self.attr_rects[a]
            y = minus_rect.y
            label = self.font.render(a, True, TEXT_COLOR)
            screen.blit(label, (30, y - 20))

            pygame.draw.rect(screen, (40, 40, 40), minus_rect)
            pygame.draw.rect(screen, (90, 90, 90), minus_rect, 1)
            m = self.font.render("-", True, TEXT_COLOR)
            screen.blit(m, (minus_rect.x + 9, minus_rect.y + 3))

            val_surf = self.font.render(str(self.attributes[a]), True, TEXT_COLOR)
            screen.blit(val_surf, (minus_rect.right + 40, y + 4))

            pygame.draw.rect(screen, (40, 40, 40), plus_rect)
            pygame.draw.rect(screen, (90, 90, 90), plus_rect, 1)
            p = self.font.render("+", True, TEXT_COLOR)
            screen.blit(p, (plus_rect.x + 7, plus_rect.y + 3))

        pool = self.attribute_pool_remaining()
        pool_surf = self.small_font.render(f"Unassigned points: {pool}", True, DIM_TEXT)
        screen.blit(pool_surf, (30, 150 + len(ATTRIBUTES) * 38 + 6))

    def _draw_trait_column(self, screen, title, trait_list, rects, accent):
        first_rect = next(iter(rects.values()))
        header = self.font.render(title, True, TITLE_COLOR)
        screen.blit(header, (first_rect.x, 62))

        for t in trait_list:
            rect = rects[t["name"]]
            selected = t["name"] in self.selected_traits
            bg = (32, 40, 32) if (selected and accent == ACCENT_COLOR) else \
                 (40, 30, 30) if (selected and accent == WARN_COLOR) else (26, 26, 26)
            pygame.draw.rect(screen, bg, rect)
            pygame.draw.rect(screen, accent if selected else (70, 70, 70), rect, 2 if selected else 1)

            sign = "-" if t["type"] == "positive" else "+"
            name_line = f'{t["name"]} ({sign}{t["cost"]})'
            name_surf = self.small_font.render(name_line, True, TEXT_COLOR)
            screen.blit(name_surf, (rect.x + 8, rect.y + 5))

            desc_surf = self.small_font.render(t["desc"], True, DIM_TEXT)
            screen.blit(desc_surf, (rect.x + 8, rect.y + 22))
