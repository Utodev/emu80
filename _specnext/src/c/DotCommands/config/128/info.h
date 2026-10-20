#ifndef INFO_H
#define INFO_H

extern unsigned char *info_core(void);
extern unsigned char *info_os(void);
extern unsigned char *info_machine(void);
extern unsigned char *info_timing(void);
extern unsigned char *info_refresh(void);
extern unsigned char *info_video(void);
extern unsigned char *info_scanlines(void);
extern unsigned char *info_cpu(void);
extern unsigned char *info_dma(void);
extern unsigned char *info_timex(void);
extern unsigned char *info_ula(void);
extern unsigned char *info_speaker(void);
extern unsigned char *info_dac(void);
extern unsigned char *info_aymode(void);
extern unsigned char *info_ay(unsigned char ay);
extern unsigned char *info_joy(unsigned char joy);

#endif
