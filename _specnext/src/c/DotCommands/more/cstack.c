#include "cstack.h"

CSTACK_DATA_TYPE cstack[CSTACK_SIZE];
unsigned int head;
unsigned int tail;

void cstack_init()
{
	head = 0;
	tail = 0;
}

void cstack_push(CSTACK_DATA_TYPE value)
{
	unsigned int temp = tail+1;
	if (temp == CSTACK_SIZE)
	{
		temp = 0;
	}

	cstack[tail] = value;
	tail = temp;

	if (tail == head)
	{
		temp = head+1;
		if (temp == CSTACK_SIZE)
		{
			temp = 0;
		}

		head = temp;
	}
}

CSTACK_DATA_TYPE cstack_pop()
{
	CSTACK_DATA_TYPE value;

	if (tail == 0)
	{
		tail = CSTACK_SIZE-1;
	}
	else
	{
		--tail;
	}
	
	value = cstack[tail];

	cstack[tail] = CSTACK_DEFAULT_VALUE;

	return value;
}

unsigned int cstack_count()
{
	if (head > tail)
	{
		return CSTACK_SIZE - tail + head;
	}

	return tail - head;	
} 