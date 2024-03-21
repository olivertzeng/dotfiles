#Copyright (c) {{_lua:os.date("%y/%m/%d %H/%M")_}} {{_author_}}. All rights reserved.

from screeninfo import get_monitors
import pygame

pygame.init()

screen = pygame.display.set_mode((get_monitors()[0].width, get_monitors()[0].height))
pygame.display.set_caption("{{_file_name_}}")

clock = pygame.time.Clock()

playing = True
while playing:
    for event in pygame.event.get():
    	if event.type == pygame.QUIT:
        	playing = False
    {{_cursor_}}
    pygame.display.update()
    clock.tick(30)
pygame.quit()
quit()
