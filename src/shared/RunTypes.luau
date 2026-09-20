--!strict

export type Phase = "Lobby" | "Dive" | "Return" | "Payout" | "GameOver"

export type Snapshot = {
	phase: Phase,
	safeZonePosition: Vector3?,
}

return {}
