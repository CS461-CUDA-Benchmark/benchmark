#ifndef mirror_bytes_H
#define mirror_bytes_H


#include "ccc/ccc.h"
#include "block128.h"


/**	Mirrors the bytes in the specified uint32.
 *	@out	out: A unit32 with the bytes mirrored.
 *	@return	NULL on success; exception_t* on failure.
 */
exception_t* mirror_bytes32(uint32 x, uint32* out);


#endif