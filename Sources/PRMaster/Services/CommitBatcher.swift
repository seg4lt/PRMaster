import Foundation

/// Helper to batch commits for AI summarization based on token limits
struct CommitBatcher {
    /// Max tokens per Claude API call (~60K tokens = ~240KB text)
    static let maxTokensPerCall = 60_000

    /// Batch limits by commit size
    static let smallBatchLimit = 30
    static let mediumBatchLimit = 6

    /// Create batches of enriched commits respecting token limits
    static func createBatches(from commits: [EnrichedCommit]) -> [[EnrichedCommit]] {
        guard !commits.isEmpty else { return [] }

        // Sort by size (small first for efficient packing)
        let sorted = commits.sorted { $0.estimatedTokens < $1.estimatedTokens }

        var batches: [[EnrichedCommit]] = []
        var currentBatch: [EnrichedCommit] = []
        var currentTokens = 0

        for commit in sorted {
            let tokens = commit.estimatedTokens

            switch commit.sizeCategory {
            case .huge:
                // Huge commits get their own batch (will be truncated during prompt building)
                if !currentBatch.isEmpty {
                    batches.append(currentBatch)
                    currentBatch = []
                    currentTokens = 0
                }
                batches.append([commit])

            case .large:
                // Large commits get their own batch
                if !currentBatch.isEmpty {
                    batches.append(currentBatch)
                    currentBatch = []
                    currentTokens = 0
                }
                batches.append([commit])

            case .medium:
                // Medium commits: batch up to 6
                if currentBatch.count >= mediumBatchLimit || currentTokens + tokens > maxTokensPerCall {
                    if !currentBatch.isEmpty {
                        batches.append(currentBatch)
                    }
                    currentBatch = [commit]
                    currentTokens = tokens
                } else {
                    currentBatch.append(commit)
                    currentTokens += tokens
                }

            case .small:
                // Small commits: batch up to 30
                if currentBatch.count >= smallBatchLimit || currentTokens + tokens > maxTokensPerCall {
                    if !currentBatch.isEmpty {
                        batches.append(currentBatch)
                    }
                    currentBatch = [commit]
                    currentTokens = tokens
                } else {
                    currentBatch.append(commit)
                    currentTokens += tokens
                }
            }
        }

        // Don't forget the last batch
        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }
}
