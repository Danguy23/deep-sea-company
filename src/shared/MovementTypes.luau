--!strict

-- Sent through the existing SprintInput remote. No client speed or velocity.
export type Intent = {
	character: Model,
	move: Vector3,
	sprint: boolean,
	jump: boolean,
}

export type Snapshot = {
	stamina: number,
	maximum: number,
	sprinting: boolean,
	exhausted: boolean,
	walkSpeed: number,
}

return {}
