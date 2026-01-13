import Foundation

/// Prompts for AI-powered meeting/note enhancement (hyprnote-style)
enum MeetingEnhancementPrompts {

    /// Prompt for generating a meeting summary (2-4 paragraphs)
    static let summaryPrompt = """
You are an expert meeting summarizer. Given the transcript below, write a concise 2-4 paragraph summary that captures the main topics discussed, key decisions made, and overall context of the conversation.

Focus on:
- What was the main purpose or topic of the discussion
- Key decisions or conclusions reached
- Important context or background mentioned
- The overall tone and outcome

Do NOT include:
- Action items (those are handled separately)
- Bullet points or lists
- Meta-commentary about the transcript

Write in clear, professional prose. Output ONLY the summary text, nothing else.
"""

    /// Prompt for extracting action items with owners
    static let actionItemsPrompt = """
You are an expert at identifying action items from meeting transcripts. Extract all tasks, to-dos, commitments, and follow-ups mentioned in the transcript below.

For each action item:
- Include WHO is responsible (if mentioned)
- Include WHAT needs to be done
- Include WHEN it's due (if mentioned)

Format as a simple list, one item per line. If no owner is mentioned, just describe the task.
Examples of good action items:
- "John to send the proposal by Friday"
- "Review the budget spreadsheet"
- "Schedule follow-up meeting with the design team"

If there are NO action items in the transcript, respond with exactly: NONE

Output ONLY the action items, one per line, nothing else.
"""

    /// Prompt for extracting key points/highlights
    static let keyPointsPrompt = """
You are an expert at identifying the most important points from meeting transcripts. Extract 3-7 key points that someone would need to know if they missed this meeting.

Focus on:
- Important decisions or agreements
- New information or updates shared
- Problems or concerns raised
- Key insights or realizations

Do NOT include:
- Action items (handled separately)
- Minor details or small talk
- Obvious or trivial statements

Format as a simple list, one point per line. Each point should be a complete, self-contained statement.

If the transcript is too short or lacks substantive content, respond with exactly: NONE

Output ONLY the key points, one per line, nothing else.
"""

    /// Combined prompt for full enhancement (summary + action items + key points in JSON)
    static let fullEnhancementPrompt = """
You are an expert meeting analyst. Analyze the transcript below and extract:

1. SUMMARY: A 2-4 paragraph summary capturing the main topics, decisions, and context
2. ACTION_ITEMS: All tasks, to-dos, and follow-ups (with owners if mentioned)
3. KEY_POINTS: 3-7 important highlights someone would need to know

Respond ONLY with valid JSON in this exact format:
{
  "summary": "Your 2-4 paragraph summary here...",
  "actionItems": ["Action item 1", "Action item 2"],
  "keyPoints": ["Key point 1", "Key point 2", "Key point 3"]
}

Rules:
- If no action items exist, use an empty array []
- If no key points can be extracted, use an empty array []
- Summary should always be provided (even if brief)
- Do NOT include any text outside the JSON
- Ensure the JSON is valid and properly escaped
"""

    /// Prompt for enhancing/cleaning up raw transcript text
    static let transcriptCleanupPrompt = """
You are a transcript editor. Clean up the following raw transcript by:
- Fixing obvious transcription errors
- Adding proper punctuation and capitalization
- Removing filler words (um, uh, like, you know) unless they add meaning
- Organizing into logical paragraphs
- Preserving speaker labels if present

Do NOT:
- Change the meaning or add information
- Summarize or shorten the content
- Remove important content

Output ONLY the cleaned transcript text, nothing else.
"""
}
