"""Shared UI panel(s) used by more than one game state."""

import pygame
from constants import LEFT_PANEL_W, SCREEN_H, PANEL_BG, PANEL_BORDER, TEXT_COLOR, NEEDS
from ui_widgets import draw_bar


def draw_needs_sidebar(screen, player, font, small_font, main_menu_rect, main_menu_label="Main Menu"):
    """Draws the left sidebar (background, Main Menu button, moves left,
    need bars, money) and returns the y-coordinate immediately below it,
    so callers can keep drawing further content (e.g. inventory slots)."""
    rect = pygame.Rect(0, 0, LEFT_PANEL_W, SCREEN_H)
    pygame.draw.rect(screen, PANEL_BG, rect)
    pygame.draw.line(screen, PANEL_BORDER, (LEFT_PANEL_W, 0), (LEFT_PANEL_W, SCREEN_H), 2)

    pygame.draw.rect(screen, (40, 40, 40), main_menu_rect)
    pygame.draw.rect(screen, PANEL_BORDER, main_menu_rect, 1)
    surf = font.render(main_menu_label, True, TEXT_COLOR)
    screen.blit(surf, (main_menu_rect.x + 10, main_menu_rect.y + 6))

    y = 50
    surf = small_font.render("Moves Left:", True, TEXT_COLOR)
    screen.blit(surf, (12, y))
    surf = font.render(f"{max(player.mp, 0)}.00/{player.max_mp}", True, TEXT_COLOR)
    screen.blit(surf, (12, y + 16))

    y += 50
    bar_w = LEFT_PANEL_W - 40
    for name in NEEDS:
        draw_bar(screen, 12, y + 16, bar_w, 12, player.needs[name], label=name, font=small_font)
        y += 40

    money_surf = font.render(f"${player.money:.2f}", True, TEXT_COLOR)
    screen.blit(money_surf, (12, y))
    y += 30

    return y
