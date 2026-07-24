import { env } from '$env/dynamic/public';

const API_URL = env.PUBLIC_API_URL ?? 'http://localhost:8080';

export interface LoginResult {
	email: string;
}

export class InvalidCredentialsError extends Error {
	constructor() {
		super('Invalid email or password');
	}
}

export async function login(email: string, password: string): Promise<LoginResult> {
	const response = await fetch(`${API_URL}/api/login`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		credentials: 'include',
		body: JSON.stringify({ email, password })
	});

	if (response.status === 401) {
		throw new InvalidCredentialsError();
	}

	if (!response.ok) {
		throw new Error('Something went wrong, try again');
	}

	return response.json();
}

export async function logout(): Promise<void> {
	await fetch(`${API_URL}/api/logout`, {
		method: 'POST',
		credentials: 'include'
	});
}
