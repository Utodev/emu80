#ifndef OPTIONS_H
#define OPTIONS_H

// Data

#define OPT_TYPE_EXACT    0
#define OPT_TYPE_LEADING  1

typedef unsigned int (*optfunc_t)(unsigned char *, unsigned int, char **);

struct opt
{
   unsigned char *name;
   unsigned char type;
   optfunc_t action;
};

#define OPT_ACTION_OK     0

struct flag
{
   unsigned char help;
};

extern struct flag flags;

// Option search and sort

extern int sort_cmp_option(struct opt *a, struct opt *b);
extern int sort_opt_search(unsigned char *name, struct opt *a);

// Options
extern unsigned int option_exec_48k(void);
extern unsigned int option_exec_128k(void);
extern unsigned int option_exec_plus3(void);
extern unsigned int option_exec_pentagon(void);
extern unsigned int option_exec_zxn(void);
extern unsigned int option_exec_lock(void);
extern unsigned int option_exec_unlock(void);
extern unsigned int option_exec_nextreg(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_nextreg_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_timing(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_timing_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_joy0(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_joy0_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_joy1(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_joy1_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_turbo_35(void);
extern unsigned int option_exec_turbo_7(void);
extern unsigned int option_exec_turbo_14(void);
extern unsigned int option_exec_50hz(void);
extern unsigned int option_exec_60hz(void);
extern unsigned int option_exec_scanline(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_scanline_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_contention(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_contention_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_aymode(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_aymode_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_ay0(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_ay0_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_ay1(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_ay1_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_ay2(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_ay2_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_speaker(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_speaker_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_timex(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_timex_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_dac(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_dac_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_dma(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_dma_eq(unsigned char *i, unsigned int argc, char **argv);
extern unsigned int option_exec_help(void);

#endif
