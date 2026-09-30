"""Small reusable UI widgets shared across screens/states."""

import pygame
from constants import (
    BUTTON_BG, BUTTON_BG_HOVER, BUTTON_BORDER, BUTTON_DISABLED,
    TEXT_COLOR, DIM_TEXT, BAR_BG, BAR_FILL, BAR_BORDER,
)


class Button:
    def __init__(self, rect, label, color=None, enabled=True):
        self.rect = pygame.Rect(rect)
        self.label = label
        self.color = color  # optional custom fill color; else default palette
        self.enabled = enabled

    def draw(self, screen, font, hovered=False):
        if not self.enabled:
            bg = BUTTON_DISABLED
        elif self.color:
            bg = self.color
        elif hovered:
            bg = BUTTON_BG_HOVER
        else:
            bg = BUTTON_BG
        pygame.draw.rect(screen, bg, self.rect)
        pygame.draw.rect(screen, BUTTON_BORDER, self.rect, 1)
        text_color = TEXT_COLOR if self.enabled else DIM_TEXT
        surf = font.render(self.label, True, text_color)
        screen.blit(surf, (self.rect.x + (self.rect.w - surf.get_width()) // 2,
                            self.rect.y + (self.rect.h - surf.get_height()) // 2))

    def clicked(self, pos):
        return self.enabled and self.rect.collidepoint(pos)


class ToggleButton(Button):
    """A button that shows a pressed/selected state (used for trait picking)."""

    def __init__(self, rect, label, color=None, selected=False):
        super().__init__(rect, label, color=color)
        self.selected = selected

    def draw(self, screen, font, hovered=False):
        super().draw(screen, font, hovered=hovered)
        if self.selected:
            pygame.draw.rect(screen, (255, 255, 255), self.rect, 2)


class TextInput:
    def __init__(self, rect, text="", max_len=20):
        self.rect = pygame.Rect(rect)
        self.text = text
        self.max_len = max_len
        self.active = False
        self._cursor_visible = True
        self._cursor_timer = 0

    def handle_event(self, event):
        if event.type == pygame.MOUSEBUTTONDOWN:
            self.active = self.rect.collidepoint(event.pos)
        elif event.type == pygame.KEYDOWN and self.active:
            if event.key == pygame.K_BACKSPACE:
                self.text = self.text[:-1]
            elif event.key in (pygame.K_RETURN, pygame.K_TAB):
                self.active = False
            elif event.unicode and event.unicode.isprintable() and len(self.text) < self.max_len:
                self.text += event.unicode

    def draw(self, screen, font):
        bg = (40, 40, 40) if self.active else (28, 28, 28)
        pygame.draw.rect(screen, bg, self.rect)
        border = (150, 150, 150) if self.active else BUTTON_BORDER
        pygame.draw.rect(screen, border, self.rect, 1)
        display_text = self.text
        if self.active and pygame.time.get_ticks() % 1000 < 500:
            display_text += "|"
        surf = font.render(display_text, True, TEXT_COLOR)
        screen.blit(surf, (self.rect.x + 8, self.rect.y + (self.rect.h - surf.get_height()) // 2))


def draw_bar(screen, x, y, w, h, value, label=None, font=None):
    pygame.draw.rect(screen, BAR_BG, (x, y, w, h))
    fill_w = int(w * max(0, min(100, value)) / 100)
    pygame.draw.rect(screen, BAR_FILL, (x, y, fill_w, h))
    pygame.draw.rect(screen, BAR_BORDER, (x, y, w, h), 1)
    px = x + fill_w
    pygame.draw.polygon(screen, (230, 210, 120), [
        (px, y - 1), (px, y + h + 1), (px + 6, y + h // 2)
    ])
    if label and font:
        surf = font.render(label, True, TEXT_COLOR)
        screen.blit(surf, (x, y - 16))
