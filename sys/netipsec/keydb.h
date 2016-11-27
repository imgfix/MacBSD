/*	$FreeBSD$	*/
/*	$KAME: keydb.h,v 1.14 2000/08/02 17:58:26 sakane Exp $	*/

/*-
 * Copyright (C) 1995, 1996, 1997, and 1998 WIDE Project.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the project nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE PROJECT AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE PROJECT OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#ifndef _NETIPSEC_KEYDB_H_
#define _NETIPSEC_KEYDB_H_

#ifdef _KERNEL

#include <sys/lock.h>
#include <sys/mutex.h>

#include <netipsec/key_var.h>

#ifndef _SOCKADDR_UNION_DEFINED
#define	_SOCKADDR_UNION_DEFINED
/*
 * The union of all possible address formats we handle.
 */
union sockaddr_union {
	struct sockaddr		sa;
	struct sockaddr_in	sin;
	struct sockaddr_in6	sin6;
};
#endif /* _SOCKADDR_UNION_DEFINED */

/* Security Assocciation Index */
/* NOTE: Ensure to be same address family */
struct secasindex {
	union sockaddr_union src;	/* source address for SA */
	union sockaddr_union dst;	/* destination address for SA */
	u_int16_t proto;		/* IPPROTO_ESP or IPPROTO_AH */
	u_int8_t mode;			/* mode of protocol, see ipsec.h */
	u_int32_t reqid;		/* reqid id who owned this SA */
					/* see IPSEC_MANUAL_REQID_MAX. */
};

/* 
 * In order to split out the keydb implementation from that of the
 * PF_KEY sockets we need to define a few structures that while they
 * may seem common are likely to diverge over time. 
 */

/* sadb_identity */
struct secident {
	u_int16_t type;
	u_int64_t id;
};

/* sadb_key */
struct seckey {
	u_int16_t bits;
	char *key_data;
};

struct seclifetime {
	u_int32_t allocations;
	u_int64_t bytes;
	u_int64_t addtime;
	u_int64_t usetime;
};

/* Security Association Data Base */
struct secashead {
	LIST_ENTRY(secashead) chain;

	struct secasindex saidx;

	struct secident *idents;	/* source identity */
	struct secident *identd;	/* destination identity */
					/* XXX I don't know how to use them. */

	u_int8_t state;			/* MATURE or DEAD. */
	LIST_HEAD(_satree, secasvar) savtree[SADB_SASTATE_MAX+1];
					/* SA chain */
					/* The first of this list is newer SA */
};

struct xformsw;
struct enc_xform;
struct auth_hash;
struct comp_algo;

/* Security Association */
struct secasvar {
	LIST_ENTRY(secasvar) chain;
	struct mtx lock;		/* update/access lock */

	u_int refcnt;			/* reference count */
	u_int8_t state;			/* Status of this Association */

	u_int8_t alg_auth;		/* Authentication Algorithm Identifier*/
	u_int8_t alg_enc;		/* Cipher Algorithm Identifier */
	u_int8_t alg_comp;		/* Compression Algorithm Identifier */
	u_int32_t spi;			/* SPI Value, network byte order */
	u_int32_t flags;		/* holder for SADB_KEY_FLAGS */

	struct seckey *key_auth;	/* Key for Authentication */
	struct seckey *key_enc;	        /* Key for Encryption */
	u_int ivlen;			/* length of IV */
	void *sched;			/* intermediate encryption key */
	size_t schedlen;
	uint64_t cntr;			/* counter for GCM and CTR */

	struct secreplay *replay;	/* replay prevention */
	time_t created;			/* for lifetime */

	struct seclifetime *lft_c;	/* CURRENT lifetime, it's constant. */
	struct seclifetime *lft_h;	/* HARD lifetime */
	struct seclifetime *lft_s;	/* SOFT lifetime */

	u_int32_t seq;			/* sequence number */
	pid_t pid;			/* message's pid */

	struct secashead *sah;		/* back pointer to the secashead */

	/*
	 * NB: Fields with a tdb_ prefix are part of the "glue" used
	 *     to interface to the OpenBSD crypto support.  This was done
	 *     to distinguish this code from the mainline KAME code.
	 */
	struct xformsw *tdb_xform;	/* transform */
	struct enc_xform *tdb_encalgxform;	/* encoding algorithm */
	struct auth_hash *tdb_authalgxform;	/* authentication algorithm */
	struct comp_algo *tdb_compalgxform;	/* compression algorithm */
	u_int64_t tdb_cryptoid;		/* crypto session id */

	/*
	 * NAT-Traversal.
	 */
	u_int16_t natt_type;		/* IKE/ESP-marker in output. */
	u_int16_t natt_esp_frag_len;	/* MTU for payload fragmentation. */
};

#define	SECASVAR_LOCK_INIT(_sav) \
	mtx_init(&(_sav)->lock, "ipsec association", NULL, MTX_DEF)
#define	SECASVAR_LOCK(_sav)		mtx_lock(&(_sav)->lock)
#define	SECASVAR_UNLOCK(_sav)		mtx_unlock(&(_sav)->lock)
#define	SECASVAR_LOCK_DESTROY(_sav)	mtx_destroy(&(_sav)->lock)
#define	SECASVAR_LOCK_ASSERT(_sav)	mtx_assert(&(_sav)->lock, MA_OWNED)
#define	SAV_ISGCM(_sav)							\
			((_sav)->alg_enc == SADB_X_EALG_AESGCM8 ||	\
			(_sav)->alg_enc == SADB_X_EALG_AESGCM12 ||	\
			(_sav)->alg_enc == SADB_X_EALG_AESGCM16)
#define	SAV_ISCTR(_sav) ((_sav)->alg_enc == SADB_X_EALG_AESCTR)
#define SAV_ISCTRORGCM(_sav)	(SAV_ISCTR((_sav)) || SAV_ISGCM((_sav)))

/* Replay prevention, protected by SECASVAR_LOCK:
 *  (m) locked by mtx
 *  (c) read only except during creation / free
 */
struct secreplay {
	u_int32_t count;	/* (m) */
	u_int wsize;		/* (c) window size, i.g. 4 bytes */
	u_int32_t seq;		/* (m) used by sender */
	u_int32_t lastseq;	/* (m) used by receiver */
	u_int32_t *bitmap;	/* (m) used by receiver */
	u_int bitmap_size;	/* (c) size of the bitmap array */
	int overflow;		/* (m) overflow flag */
};

/* socket table due to send PF_KEY messages. */
struct secreg {
	LIST_ENTRY(secreg) chain;

	struct socket *so;
};

/* acquiring list table. */
struct secacq {
	LIST_ENTRY(secacq) chain;

	struct secasindex saidx;

	u_int32_t seq;		/* sequence number */
	time_t created;		/* for lifetime */
	int count;		/* for lifetime */
};

/* Sensitivity Level Specification */
/* nothing */

#define SADB_KILL_INTERVAL	600	/* six seconds */

/* secpolicy */
extern struct secpolicy *keydb_newsecpolicy(void);
extern void keydb_delsecpolicy(struct secpolicy *);
/* secashead */
extern struct secashead *keydb_newsecashead(void);
extern void keydb_delsecashead(struct secashead *);
/* secasvar */
extern struct secasvar *keydb_newsecasvar(void);
extern void keydb_refsecasvar(struct secasvar *);
extern void keydb_freesecasvar(struct secasvar *);
/* secreplay */
extern struct secreplay *keydb_newsecreplay(size_t);
extern void keydb_delsecreplay(struct secreplay *);
/* secreg */
extern struct secreg *keydb_newsecreg(void);
extern void keydb_delsecreg(struct secreg *);

#endif /* _KERNEL */

#endif /* _NETIPSEC_KEYDB_H_ */
