import Base

# Aggregate all domain law witnesses for one complete proof check.
import ./proofs/BitTreeProof.bend as BitTreeProof
import ./proofs/BloomSafeProof.bend as BloomSafeProof
import ./proofs/BloomScheduleProof.bend as BloomScheduleProof
import ./proofs/BloomTreeProof.bend as BloomTreeProof
import ./proofs/BloomZeroEstimateProof.bend as BloomZeroEstimateProof
import ./proofs/CompactProof.bend as CompactProof
import ./proofs/CrashPointProof.bend as CrashPointProof
import ./proofs/DbProof.bend as DbProof
import ./proofs/DecimalProof.bend as DecimalProof
import ./proofs/DemoProof.bend as DemoProof
import ./proofs/FlushProof.bend as FlushProof
import ./proofs/KeysProof.bend as KeysProof
import ./proofs/ManifestProof.bend as ManifestProof
import ./proofs/MemTableProof.bend as MemTableProof
import ./proofs/MergeIterProof.bend as MergeIterProof
import ./proofs/RecoverProof.bend as RecoverProof
import ./proofs/ReplProof.bend as ReplProof
import ./proofs/SortedRunProof.bend as SortedRunProof
import ./proofs/SstFileDispatchV2Proof.bend as SstFileDispatchV2Proof
import ./proofs/SstFileParserProof.bend as SstFileParserProof
import ./proofs/SstFileRejectProof.bend as SstFileRejectProof
import ./proofs/SstFileRoundtripProof.bend as SstFileRoundtripProof
import ./proofs/SstFileV2ChecksumProof.bend as SstFileV2ChecksumProof
import ./proofs/SstFileV2DeleteProof.bend as SstFileV2DeleteProof
import ./proofs/SstFileV2DescendingProof.bend as SstFileV2DescendingProof
import ./proofs/SstFileV2DuplicateProof.bend as SstFileV2DuplicateProof
import ./proofs/SstFileV2ParserProof.bend as SstFileV2ParserProof
import ./proofs/SstFileV2PutProof.bend as SstFileV2PutProof
import ./proofs/SstStreamProof.bend as SstStreamProof
import ./proofs/SstableProof.bend as SstableProof
import ./proofs/StorageBytesProof.bend as StorageBytesProof
import ./proofs/WalProof.bend as WalProof
