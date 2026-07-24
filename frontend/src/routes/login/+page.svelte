<script lang="ts">
	import { goto } from '$app/navigation';
	import { login, InvalidCredentialsError } from '$lib/api';

	let email = $state('');
	let password = $state('');
	let loading = $state(false);
	let errorMessage = $state('');

	async function handleSubmit(event: SubmitEvent) {
		event.preventDefault();
		errorMessage = '';
		loading = true;

		try {
			await login(email, password);
			await goto('/');
		} catch (error) {
			errorMessage =
				error instanceof InvalidCredentialsError
					? error.message
					: 'Something went wrong, try again';
		} finally {
			loading = false;
		}
	}
</script>

<form onsubmit={handleSubmit}>
	<h1>Log in</h1>

	<label for="email">Email</label>
	<input id="email" type="email" bind:value={email} required autocomplete="email" />

	<label for="password">Password</label>
	<input
		id="password"
		type="password"
		bind:value={password}
		required
		autocomplete="current-password"
	/>

	{#if errorMessage}
		<p role="alert">{errorMessage}</p>
	{/if}

	<button type="submit" disabled={loading}>
		{loading ? 'Logging in…' : 'Log in'}
	</button>
</form>
