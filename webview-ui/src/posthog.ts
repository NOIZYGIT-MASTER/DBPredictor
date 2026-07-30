import posthog from 'posthog-js';

const key = import.meta.env.VITE_POSTHOG_KEY as string | undefined;
const host = import.meta.env.VITE_POSTHOG_HOST as string | undefined;

if (!key) {
    if (import.meta.env.DEV) {
        throw new Error(
            'VITE_POSTHOG_KEY variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once VITE_POSTHOG_KEY is configured'
        );
    }
} else {
    posthog.init(key, {
        api_host: host ?? 'https://us.i.posthog.com',
        defaults: '2026-05-30',
    });
}

export default posthog;
