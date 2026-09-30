"""Title screen: load an existing save, start a new character, or quit."""

import sys
import pygame
from constants import SCREEN_W, SCREEN_H, MENU_BG, TITLE_COLOR, DIM_TEXT
from ui_widgets import Button
import save_load


class MainMenuState:
    def __init__(self, manager):
        self.manager = manager
        self.font = pygame.font.SysFont(None, 22)
        self.title_font = pygame.font.SysFont(None, 48, bold=True)

        has_save = save_load.save_exists()

        cx = SCREEN_W // 2
        self.new_game_btn = Button((cx - 110, 260, 220, 44), "New Character")
        self.continue_btn = Button((cx - 110, 316, 220, 44), "Continue Saved Game", enabled=has_save)
        self.quit_btn = Button((cx - 110, 372, 220, 44), "Quit")

        self.status = "" if has_save else "No saved game found."

    def handle_event(self, event):
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if self.new_game_btn.clicked(event.pos):
                from state_character_creator import CharacterCreatorState
                self.manager.change_state(CharacterCreatorState(self.manager))
            elif self.continue_btn.clicked(event.pos):
                result = save_load.load_game()
                if result is None:
                    self.status = "Save file couldn't be read."
                    self.continue_btn.enabled = False
                else:
                    player, tiles, ground_items = result
                    from state_overworld import OverworldState
                    self.manager.change_state(OverworldState(self.manager, player, tiles, ground_items))
            elif self.quit_btn.clicked(event.pos):
                pygame.quit()
                sys.exit()

    def update(self):
        pass

    def draw(self, screen):
        screen.fill(MENU_BG)
        title = self.title_font.render("WASTELAND SURVIVOR", True, TITLE_COLOR)
        screen.blit(title, (SCREEN_W // 2 - title.get_width() // 2, 150))

        mouse_pos = pygame.mouse.get_pos()
        for btn in (self.new_game_btn, self.continue_btn, self.quit_btn):
            btn.draw(screen, self.font, hovered=btn.rect.collidepoint(mouse_pos))

        if self.status:
            surf = self.font.render(self.status, True, DIM_TEXT)
            screen.blit(surf, (SCREEN_W // 2 - surf.get_width() // 2, 440))
