;    ZXZVM: Z-Code interpreter for the Z80 processor
;    Copyright (C) 1998-9,2006,2016  John Elliott <seasip.webmaster@gmail.com>
;
;    This program is free software; you can redistribute it and/or modify
;    it under the terms of the GNU General Public License as published by
;    the Free Software Foundation; either version 2 of the License, or
;    (at your option) any later version.
;
;    This program is distributed in the hope that it will be useful,
;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;    GNU General Public License for more details.
;
;    You should have received a copy of the GNU General Public License
;    along with this program; if not, write to the Free Software
;    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

; 2019-05-17, Garry Lancaster: New file


; ***************************************************************************
; * ZX Spectrum Next hardware defines                                       *
; ***************************************************************************

; Config registers
next_reg_select                         equ     $243b
next_reg_access                         equ     $253b

; Max 28MHz.
turbo_mask                              equ     3
turbo_max                               equ     3

nxr_corever                             equ     $01
nxr_reset                               equ     $02
nxr_peripheral1                         equ     $05
nxr_peripheral2                         equ     $06
nxr_turbo                               equ     $07
nxr_peripheral3                         equ     $08
nxr_peripheral4                         equ     $09
nxr_coresubminor                        equ     $0e
nxr_l2page                              equ     $12
nxr_l2shadow                            equ     $13
nxr_transparency                        equ     $14
nxr_sprites                             equ     $15
nxr_layer2x                             equ     $16
nxr_layer2y                             equ     $17
nxr_clip_l2                             equ     $18
nxr_clip_sprite                         equ     $19
nxr_clip_ula                            equ     $1a
nxr_clip_tilemap                        equ     $1b
nxr_clip_index                          equ     $1c
nxr_lineint_control                     equ     $22
nxr_tilemapx_msb                        equ     $2f
nxr_tilemapx_lsb                        equ     $30
nxr_tilemapy                            equ     $31
nxr_ulax                                equ     $32
nxr_ulay                                equ     $33
nxr_sprite_num                          equ     $34
nxr_palette_index                       equ     $40
nxr_palette_value8                      equ     $41
nxr_palette_format                      equ     $42
nxr_palette_control                     equ     $43
nxr_palette_value9                      equ     $44
nxr_transp_fallback                     equ     $4a
nxr_transp_sprites                      equ     $4b
nxr_transp_tilemap                      equ     $4c
nxr_mmu0                                equ     $50
nxr_mmu1                                equ     $51
nxr_mmu2                                equ     $52
nxr_mmu3                                equ     $53
nxr_mmu4                                equ     $54
nxr_mmu5                                equ     $55
nxr_mmu6                                equ     $56
nxr_mmu7                                equ     $57
nxr_cudata                              equ     $60
nxr_cuctrl_lo                           equ     $61
nxr_cuctrl_hi                           equ     $62
nxr_ula_ctrl                            equ     $68
nxr_tilemap_ctrl                        equ     $6b
nxr_tilemap_attr                        equ     $6c
nxr_tilemap_base                        equ     $6e
nxr_tiledefs_base                       equ     $6f

transparency_default                    equ     $e3

; Sprite ports
nxp_sprite      equ     $303b
nxp_spr_pal     equ     $53
nxp_spr_attr    equ     $57
nxp_spr_data    equ     $5b

; Layer2 ports
nxp_layer2      equ     $123b
nxv_l2_write    equ     $01
nxv_l2_visible  equ     $02
nxv_l2_back     equ     $08
nxv_l2_vram0    equ     $00
nxv_l2_vram1    equ     $40
nxv_l2_vram2    equ     $80
nxv_l2_vrammask equ     $c0

NUM_SPRITES     equ     64

