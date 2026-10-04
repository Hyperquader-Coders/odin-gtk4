/* Stub for runic's libclang, which finds no compiler headers. graphene-config.h includes
 * this for GRAPHENE_USE_SSE and typedefs graphene_simd4f_t to __m128; rune.yml overwrites
 * graphene_simd4f_t with its four floats, so only the type has to exist. */
#pragma once
typedef float __m128 __attribute__((vector_size(16)));
