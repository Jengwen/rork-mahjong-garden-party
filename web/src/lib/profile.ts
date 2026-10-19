// Shared player profile — the same `player_profiles` row the iOS app reads and
// writes (see ios/.../Models/SupabaseModels.swift and AppViewModel.swift).
import { supabase } from './supabase';

/** Mirrors ProfileSettings.swift. iOS decodes this strictly: ALWAYS write every key. */
export interface ProfileSettings {
  soundEnabled: boolean;
  hapticsEnabled: boolean;
  musicEnabled: boolean;
  soundVolume: number;
  notificationsEnabled: boolean;
  turnReminders: boolean;
  friendRequests: boolean;
  gameInvites: boolean;
  showOnlineStatus: boolean;
  showGameHistory: boolean;
  allowFriendRequests: boolean;
  autoSortHand: boolean;
  confirmDiscards: boolean;
}

export const DEFAULT_SETTINGS: ProfileSettings = {
  soundEnabled: true, hapticsEnabled: true, musicEnabled: true, soundVolume: 0.8,
  notificationsEnabled: true, turnReminders: true, friendRequests: true, gameInvites: true,
  showOnlineStatus: true, showGameHistory: true, allowFriendRequests: true,
  autoSortHand: false, confirmDiscards: true,
};

export function normalizeSettings(raw: unknown): ProfileSettings {
  const out = { ...DEFAULT_SETTINGS };
  if (raw && typeof raw === 'object') {
    for (const k of Object.keys(DEFAULT_SETTINGS) as (keyof ProfileSettings)[]) {
      const v = (raw as Record<string, unknown>)[k];
      if (typeof v === typeof DEFAULT_SETTINGS[k]) (out as Record<string, unknown>)[k] = v;
    }
  }
  return out;
}

export interface Profile {
  user_id: string;
  display_name: string;
  avatar_image: string;
  email: string;
  level: number;
  xp: number;
  total_wins: number;
  total_games: number;
  current_streak: number;
  selected_theme_id: string;
  unlocked_themes: string[];
  unlocked_tile_sets: string[];
  settings_data: ProfileSettings;
}

export const xpForNextLevel = (level: number) => level * 500;

function fromRow(row: Record<string, unknown>, userId: string): Profile {
  return {
    user_id: userId,
    display_name: (row.display_name as string) || 'Garden Guest',
    avatar_image: (row.avatar_image as string) || 'daffodil',
    email: (row.email as string) || '',
    level: (row.level as number) ?? 1,
    xp: (row.xp as number) ?? 0,
    total_wins: (row.total_wins as number) ?? 0,
    total_games: (row.total_games as number) ?? 0,
    current_streak: (row.current_streak as number) ?? 0,
    selected_theme_id: (row.selected_theme_id as string) || 'garden_party',
    unlocked_themes: (row.unlocked_themes as string[]) ?? ['garden_party'],
    unlocked_tile_sets: (row.unlocked_tile_sets as string[]) ?? ['classic'],
    settings_data: normalizeSettings(row.settings_data),
  };
}

export async function fetchProfile(userId: string): Promise<Profile | null> {
  const { data, error } = await supabase.from('player_profiles').select('*').eq('user_id', userId).maybeSingle();
  if (error) throw error;
  return data ? fromRow(data, userId) : null;
}

/** First sign-in on web for an account that has no profile row yet (matches iOS createInitialProfile). */
export async function ensureProfile(userId: string, email: string, displayName?: string): Promise<Profile> {
  const existing = await fetchProfile(userId);
  if (existing) return existing;
  const row = {
    user_id: userId,
    display_name: displayName?.trim() || 'Garden Guest',
    avatar_image: 'daffodil',
    email,
    selected_theme_id: 'garden_party',
    settings_data: DEFAULT_SETTINGS,
  };
  const { error } = await supabase.from('player_profiles').insert(row);
  if (error && error.code !== '23505') throw error;
  return (await fetchProfile(userId)) ?? fromRow(row, userId);
}

/** Update profile fields. Settings are re-fetched and merged so phone-only settings survive. */
export async function updateProfile(
  userId: string,
  patch: Partial<Pick<Profile, 'display_name' | 'avatar_image'>> & { settings?: Partial<ProfileSettings> },
): Promise<Profile> {
  const update: Record<string, unknown> = {};
  if (patch.display_name !== undefined) update.display_name = patch.display_name;
  if (patch.avatar_image !== undefined) update.avatar_image = patch.avatar_image;
  if (patch.settings) {
    const latest = await fetchProfile(userId);
    update.settings_data = { ...normalizeSettings(latest?.settings_data), ...patch.settings };
  }
  update.updated_at = new Date().toISOString();
  const { error } = await supabase.from('player_profiles').update(update).eq('user_id', userId);
  if (error) throw error;
  return (await fetchProfile(userId))!;
}

export type MatchResult = 'Win' | 'Loss' | 'Draw';

export interface GameResultRow {
  id: string;
  result: MatchResult;
  score: number;
  opponent_names: string[];
  game_mode: string;
  played_at: string;
}

export async function fetchRecentResults(userId: string, limit = 20): Promise<GameResultRow[]> {
  const { data, error } = await supabase.from('game_results').select('id,result,score,opponent_names,game_mode,played_at')
    .eq('user_id', userId).order('played_at', { ascending: false }).limit(limit);
  if (error) throw error;
  return (data ?? []) as GameResultRow[];
}

/**
 * Record a finished game. Uses the atomic `record_game_result` RPC so a game
 * finished on the web and one finished on the phone can never overwrite each
 * other's totals. Falls back to a fresh read-modify-write (the same rules as
 * iOS AppViewModel.recordGameResult) if the RPC hasn't been deployed yet.
 */
export async function recordGameResult(
  userId: string, result: MatchResult, score: number, opponents: string[], mode = 'Solo Practice',
): Promise<Profile | null> {
  const rpc = await supabase.rpc('record_game_result', {
    p_result: result, p_score: score, p_opponents: opponents, p_mode: mode,
  });
  if (!rpc.error) return fetchProfile(userId);
  if (rpc.error.code !== 'PGRST202' && rpc.error.code !== '42883') throw rpc.error;

  // Fallback: identical math to iOS (win +100 XP & streak, otherwise +25 XP & streak reset).
  const p = await fetchProfile(userId);
  if (!p) return null;
  const won = result === 'Win';
  let xp = p.xp + (won ? 100 : 25);
  let level = p.level;
  if (xp >= xpForNextLevel(level)) { xp -= xpForNextLevel(level); level += 1; }
  const { error: upErr } = await supabase.from('player_profiles').update({
    total_games: p.total_games + 1,
    total_wins: p.total_wins + (won ? 1 : 0),
    current_streak: won ? p.current_streak + 1 : 0,
    xp, level, updated_at: new Date().toISOString(),
  }).eq('user_id', userId);
  if (upErr) throw upErr;
  const { error: insErr } = await supabase.from('game_results').insert({
    user_id: userId, result, score, opponent_names: opponents, game_mode: mode,
  });
  if (insErr) throw insErr;
  return fetchProfile(userId);
}
