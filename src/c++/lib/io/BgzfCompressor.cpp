/**
 ** Copyright (c) 2014 Illumina, Inc.
 **
 ** This file is part of Illumina's Enhanced Artificial Genome Engine (EAGLE),
 ** covered by the "BSD 2-Clause License" (see accompanying LICENSE file)
 **
 ** \description implements bgzf filtering stream by buffering the compressed data and
 ** rewriting gzip header generated by boost::iostreams::gzip_compressor.
 **
 ** \author Roman Petrovski
 **/

#include "io/BgzfCompressor.hh"


namespace eagle
{
namespace io
{
namespace bam
{


void BgzfCompressor::rewriteHeader()
{
    memmove(&bgzf_buffer[0], &bgzf_buffer[sizeof(BAM_XFIELD)], sizeof(Header) - sizeof(BAM_XFIELD));
    Header *h(reinterpret_cast<Header*>(&bgzf_buffer[0]));
    h->xfield = makeBamXfield();
    h->FLG |= 0x04; // tell gzip that XLEN is in effect now.
}

void BgzfCompressor::initBuffer()
{
    bgzf_buffer.clear();
    uncompressed_in_ = 0;
    bgzf_buffer.insert(bgzf_buffer.begin(), sizeof(BAM_XFIELD), 0); //make some room for xfield

//    std::clog << "buffer init size: " << bgzf_buffer.size() << "\n";

}

BgzfCompressor::BgzfCompressor(const bios::gzip_params& gzip_params):
    gzip_params_(gzip_params),
    compressor_(gzip_params_),
    uncompressed_in_(0)
{
    bgzf_buffer.reserve(max_uncompressed_per_block_ + sizeof(Header)); //single chunk cannot hold more than 65535 compressed bytes
    initBuffer();
}

BgzfCompressor::BgzfCompressor(const BgzfCompressor& that):
    gzip_params_(that.gzip_params_),
    compressor_(gzip_params_),
    uncompressed_in_(0)
{
    bgzf_buffer.reserve(max_uncompressed_per_block_ + sizeof(Header)); //single chunk cannot hold more than 65535 compressed bytes
    initBuffer();
}

void BgzfCompressor::close()
{
}


} // namespace bam
} // namespace io
} // namespace eagle
