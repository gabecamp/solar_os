"""
Entry point. Run this file to play.

  pip install pygame
  python3 main.py

Starts at the main menu, which routes to either the character creator
(new game) or straight into the overworld (continue saved game).
"""

import sys
import pygame
from constants import SCREEN_W, SCREEN_H, FPS, BG_COLOR


class StateManager:
    def __init__(self):
        pygame.init()
        self.screen = pygame.display.set_mode((SCREEN_W, SCREEN_H))
        pygame.display.set_caption("Wasteland Survivor - prototype")
        self.clock = pygame.time.Clock()
        self.running = True

        from state_main_menu import MainMenuState
        self.state = MainMenuState(self)

    def change_state(self, new_state):
        self.state = new_state

    def run(self):
        while self.running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                else:
                    self.state.handle_event(event)

            self.state.update()
            self.screen.fill(BG_COLOR)
            self.state.draw(self.screen)
            pygame.display.flip()
            self.clock.tick(FPS)

        pygame.quit()
        sys.exit()


if __name__ == "__main__":
    StateManager().run()
